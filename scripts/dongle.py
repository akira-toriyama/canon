#!/usr/bin/env python3
# Which USB device is which dongle, and a serial log reader that follows them.
#
# The one place that identifies the dongles on USB: flash-dongle.sh takes the
# image's device, the port, USB location and serial, and the owner of the
# bootloader volume from the plumbing subcommands (image, find, owner).
#
# Identity is the USB product string alone. Both dongles (and the ist dongle
# of zmk-ble-hid-host) carry ZMK's default VID/PID 0x1D50/0x615E, and a
# /dev/cu.usbmodem* name is derived from the USB location (0x02112000 ->
# usbmodem211201): never identify a dongle by either.
#
# `log` sets a port to 115200 8N1 and to no other rate: a rate of 1200 reboots
# either dongle into its UF2 bootloader (zmk-beacon
# src/bootloader_on_1200_baud.c acts on any change of the line coding to
# 1200), and 2400 is reserved for a screen dump zmk-beacon will add. It never
# sets TIOCEXCL: flash-dongle.sh's stty must still open a port that a reader
# holds, and the reader then follows the dongle through the bootloader into
# the new image's boot log.
#
# Stdlib only, and it runs on the Command Line Tools' /usr/bin/python3 (3.9):
# no match statements, no X | Y type unions.

import argparse
import datetime
import fcntl
import glob
import hashlib
import math
import os
import plistlib
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
from collections import namedtuple

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

# Build target (build.yaml shield) -> USB product string. Contracts:
#   prospector      CONFIG_USB_DEVICE_PRODUCT in zmk-beacon's
#                   boards/shields/prospector/prospector.conf
#   imprint_dongle  ZMK_KEYBOARD_NAME in zmk-keyboards'
#                   boards/shields/imprint_dongle/Kconfig.defconfig, which
#                   chord's VKeyHIDSource matches too (canon CLAUDE.md)
DEVICES = {
    "prospector": "Prospector Dongle",
    "imprint_dongle": "Imprint Dongle",
}

VOLUME = "/Volumes/XIAO-SENSE"
FLASHERS = r"flash-(watch|reset|impl)\.sh"  # flash-dongle.sh's guard pattern
US = "\x1f"  # plumbing field separator: a tab would collapse empty fields under IFS
POLL_S = 0.2
MAX_LINE = 65536

# Lines that carry a keycode, a HID usage, a key position, modifier state or a
# key's press and release. From the LOG_DBG calls of ZMK main 5b51501f app/src
# (hid_listener, hid, keymap, behaviors, combo, split central, wpm) and canon's
# vkey patch. Debug lines lead with their function's name
# (CONFIG_LOG_FUNC_NAME_PREFIX_DBG, on by default), so hold-tap lines such as
# "decide_hold_tap: 23 decided tap" match by it; the message words cover a
# build without that prefix. Kept on purpose: zmk-beacon's keystroke counts
# and the split discovery line "Found position state characteristic".
KEY_EVENT = re.compile(
    r"keycode|usage|position|modifier|implicit.?mods|explicit.?mods"
    r"|hold.?tap|retro.?tap|tap.?dance|sticky.?key|caps.?word|combo|macro"
    r"|mouse|button|pressed|released|decision moment|bubbl|capturing",
    re.I,
)
KEY_EVENT_KEPT = re.compile(r"characteristic", re.I)

# ANSI escape sequences (CSI, and two-byte Fe) and the C0 controls but tab.
ESCAPES = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|[@-Z\\-_])|[\x00-\x08\x0b-\x1f\x7f]")

UsbDevice = namedtuple("UsbDevice", "product serial session location ports dialins")


class Failure(Exception):
    """A message for stderr and an exit status."""

    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status


def ioreg(*args):
    try:
        raw = subprocess.run(["ioreg", "-a", *args], capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        raise Failure("ioreg failed: %s" % e)
    roots = plistlib.loads(raw) if raw.strip() else []
    return roots if isinstance(roots, list) else [roots]


def children(node):
    kids = node.get("IORegistryEntryChildren", [])
    return [kids] if isinstance(kids, dict) else kids  # -t: a lone child is a dict


def walk(node, usb=None):
    """Each node below node, with the nearest IOUSBHostDevice at or above it."""
    if node.get("IOObjectClass") == "IOUSBHostDevice":
        usb = node
    yield node, usb
    for kid in children(node):
        yield from walk(kid, usb)


def usb_device(node, ports=(), dialins=()):
    return UsbDevice(
        product=str(node.get("kUSBProductString", "")),
        serial=str(node.get("kUSBSerialNumberString", "")),
        session=node.get("sessionID"),
        location="0x%08x" % node.get("locationID", 0),
        ports=tuple(sorted(ports)),
        dialins=tuple(sorted(dialins)),
    )


def find(products):
    """The USB devices whose product string is in products, with their ports.

    Product strings are the descriptor strings (kUSBProductString; "USB
    Product Name" is macOS's sanitised copy, "-" becomes "_"). The IOUSB plane
    has no class subtrees, so it stays fast behind USB disks. Serial clients
    come with their ancestors (-t), so the nearest IOUSBHostDevice above a
    port is the device it belongs to.
    """
    hits = {}
    for root in ioreg("-p", "IOUSB", "-l"):
        for node, usb in walk(root):
            if node is usb and node.get("kUSBProductString") in products:
                hits.setdefault(node.get("sessionID"), node)
    if not hits:
        return []
    callouts, dialins = {}, {}
    for root in ioreg("-r", "-t", "-c", "IOSerialBSDClient", "-l"):
        for node, usb in walk(root):
            if "IOCalloutDevice" in node and usb is not None:
                session = usb.get("sessionID")
                callouts.setdefault(session, set()).add(node["IOCalloutDevice"])
                if "IODialinDevice" in node:
                    dialins.setdefault(session, set()).add(node["IODialinDevice"])
    return [
        usb_device(node, callouts.get(session, ()), dialins.get(session, ()))
        for session, node in hits.items()
    ]


def mounted_disk(mountpoint):
    """The BSD name (diskN or diskNsM) mounted exactly at mountpoint, else None.

    df names the enclosing file system for a path that is not a mount point.
    Not diskutil: right after a mount it can answer "Could not find disk".
    """
    try:
        lines = subprocess.run(["df", "-P", mountpoint], capture_output=True, text=True).stdout.splitlines()
    except OSError:
        return None
    fields = lines[1].split(None, 5) if len(lines) > 1 else []
    if len(fields) == 6 and fields[5] == mountpoint and fields[0].startswith("/dev/"):
        return fields[0][len("/dev/"):]
    return None


def disk_owner(bsd_name):
    """The USB device that is the nearest ancestor of that IOMedia, else None."""
    for root in ioreg("-r", "-t", "-c", "IOMedia", "-l"):
        for node, usb in walk(root):
            if node.get("BSD Name") == bsd_name and usb is not None:
                return usb_device(usb)
    return None


def uf2_payload(data):
    """The blocks' payloads joined in target-address order, None for no UF2.

    Joined, a string that straddles two blocks still matches.
    """
    if not data or len(data) % 512:
        return None
    chunks = {}
    for off in range(0, len(data), 512):
        magic0, magic1, _flags, addr, size = struct.unpack_from("<5I", data, off)
        (magic_end,) = struct.unpack_from("<I", data, off + 508)
        if (magic0, magic1, magic_end) != (0x0A324655, 0x9E5D5157, 0x0AB16F30) or size > 476:
            return None
        chunks[addr] = data[off + 32:off + 32 + size]
    return b"".join(chunks[a] for a in sorted(chunks))


def clean(raw):
    return ESCAPES.sub("", raw.decode("utf-8", "replace")).rstrip()


def split_lines(buf):
    """The complete lines in buf and the unterminated rest."""
    *lines, rest = buf.split(b"\n")
    return lines, rest


def is_key_event(line):
    return bool(KEY_EVENT.search(line)) and not KEY_EVENT_KEPT.search(line)


def port_holders(device):
    """'cmd[pid]' of each process holding one of the device's port nodes."""
    paths = [p for p in device.ports + device.dialins if os.path.exists(p)]
    if not paths:
        return []
    try:
        out = subprocess.run(["lsof", "-w", "-Fpc", "--", *paths], capture_output=True, text=True).stdout
    except OSError:
        return ["(lsof unavailable)"]
    holders, pid = [], None
    for line in out.splitlines():
        if line.startswith("p"):
            pid = line[1:]
        elif line.startswith("c") and pid is not None:
            holders.append("%s[%s]" % (line[1:], pid))
    return list(dict.fromkeys(holders))


def repository_roots():
    """This checkout, and the main checkout when this one is a git worktree."""
    roots = [REPO]
    try:
        common = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return roots
    if common:
        roots.append(os.path.dirname(common))
    return roots


def is_inside(path, root):
    """Whether path (symlinks resolved) lies in root. samefile, not a string
    prefix: firmlinks and case-insensitive volumes spell one directory in
    several ways."""
    d = os.path.dirname(os.path.realpath(path))
    while True:
        try:
            if os.path.samefile(d, root):
                return True
        except OSError:
            pass
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def open_port(path):
    """The port opened raw 8N1 at 115200 with DTR and RTS up (ZMK's USB
    logging stays silent until the host raises DTR). No HUPCL: closing leaves
    DTR up."""
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        attrs = termios.tcgetattr(fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = attrs[5] = termios.B115200
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        fcntl.ioctl(fd, termios.TIOCMBIS, struct.pack("I", termios.TIOCM_DTR | termios.TIOCM_RTS))
    except BaseException:
        os.close(fd)
        raise
    return fd


class Reader:
    def __init__(self, device):
        self.device = device
        self.product = DEVICES[device]
        self.fd = None
        self.port = None
        self.buf = b""
        self.state = None  # last host event said about a closed port, to say each once
        self.opens = self.lines = self.printed = self.dropped = 0


class LogSession:
    def __init__(self, devices, seconds, grep, raw, out):
        self.readers = [Reader(d) for d in devices]
        self.seconds = seconds
        self.grep = grep
        self.raw = raw
        self.out = out
        self.signals = []
        self.next_poll = 0.0
        self.stdout_gone = False

    def emit(self, reader, mark, text):
        stamp = datetime.datetime.now().strftime("%m-%d %H:%M:%S.%f")[:-3]
        line = "%s %s %s %s" % (stamp, reader.device, mark, text)
        if not self.stdout_gone:
            try:
                print(line, flush=True)
            except BrokenPipeError:
                # The reader of stdout left (| head): stop, and keep the
                # interpreter's final flush from failing on the pipe.
                self.stdout_gone = True
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        if self.out is not None:
            self.out.write(line + "\n")
            self.out.flush()

    def event(self, reader, text):
        self.emit(reader, "#", text)

    def line(self, reader, raw):
        text = clean(raw)
        if not text:
            return
        reader.lines += 1
        if not self.raw and is_key_event(text):
            reader.dropped += 1
            return
        if self.grep is not None and not self.grep.search(text):
            return
        reader.printed += 1
        self.emit(reader, "|", text)

    def say_state(self, reader, state, prefix=""):
        if state != reader.state:
            reader.state = state
            self.event(reader, prefix + state)

    @staticmethod
    def waiting(reader):
        return 'waiting for "%s" with a port, polling every %.1f s' % (reader.product, POLL_S)

    def reopen(self, closed):
        by_product = {}
        try:
            devices = find({r.product for r in closed})
        except Failure as e:
            for r in closed:
                self.say_state(r, str(e))
            return
        for dev in devices:
            by_product.setdefault(dev.product, []).append(dev)
        for r in closed:
            with_port = [d for d in by_product.get(r.product, []) if d.ports]
            if len(with_port) != 1:
                if len(with_port) > 1:
                    self.say_state(r, '%d USB devices named "%s"; leave exactly one plugged in' % (len(with_port), r.product))
                else:
                    self.say_state(r, self.waiting(r))
                continue
            dev = with_port[0]
            try:
                r.fd = open_port(dev.ports[0])
            except (OSError, termios.error) as e:  # termios.error is no OSError
                # A port that is still attaching can open and then fail termios.
                self.say_state(r, "cannot open %s yet: %s" % (dev.ports[0], e.args[-1]))
                continue
            r.port, r.state, r.buf = dev.ports[0], None, b""
            r.opens += 1
            self.event(r, "open %s serial=%s location=%s" % (r.port, dev.serial or "-", dev.location))

    def lose(self, reader, why):
        if reader.buf:
            self.line(reader, reader.buf)
            reader.buf = b""
        try:
            os.close(reader.fd)
        except OSError:
            pass
        reader.fd = None
        self.say_state(reader, self.waiting(reader), "lost %s (%s); " % (reader.port, why))

    def pump(self, reader):
        try:
            chunk = os.read(reader.fd, 4096)
        except (BlockingIOError, InterruptedError):
            return
        except OSError as e:
            self.lose(reader, e.strerror or str(e))
            return
        if not chunk:
            self.lose(reader, "end of file")
            return
        lines, reader.buf = split_lines(reader.buf + chunk)
        for raw in lines:
            self.line(reader, raw)
        if len(reader.buf) > MAX_LINE:
            self.line(reader, reader.buf)
            reader.buf = b""

    def run(self):
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, lambda signum, _frame: self.signals.append(signum))
        deadline = time.monotonic() + self.seconds
        until = datetime.datetime.now() + datetime.timedelta(seconds=self.seconds)
        print("dongle.py log: pid %d, %s for %g s (until %s); stop early with: kill %d"
              % (os.getpid(), " ".join(r.device for r in self.readers), self.seconds,
                 until.strftime("%H:%M:%S"), os.getpid()), file=sys.stderr, flush=True)
        try:
            while not self.signals and not self.stdout_gone:
                now = time.monotonic()
                if now >= deadline:
                    break
                closed = [r for r in self.readers if r.fd is None]
                if closed and now >= self.next_poll:
                    self.next_poll = now + POLL_S
                    self.reopen(closed)
                open_fds = {r.fd: r for r in self.readers if r.fd is not None}
                timeout = min(deadline - time.monotonic(), 0.5)
                if len(open_fds) < len(self.readers):
                    timeout = min(timeout, self.next_poll - time.monotonic())
                timeout = max(timeout, 0.0)
                if not open_fds:
                    time.sleep(timeout)
                    continue
                try:
                    ready, _, _ = select.select(list(open_fds), [], [], timeout)
                except OSError:
                    ready = list(open_fds)  # a port that vanished under select: its read fails
                for fd in ready:
                    self.pump(open_fds[fd])
        finally:
            for r in self.readers:
                if r.buf:
                    self.line(r, r.buf)
                if r.fd is not None:
                    try:
                        os.close(r.fd)
                    except OSError:
                        pass
        for r in self.readers:
            kept = " (--raw keeps them)" if r.dropped and not self.raw else ""
            print("dongle.py log: %s: opened %d times, %d lines, %d printed, %d key-event lines dropped%s"
                  % (r.device, r.opens, r.lines, r.printed, r.dropped, kept), file=sys.stderr)
        if self.signals:
            return 128 + self.signals[0]
        missing = [r.device for r in self.readers if not r.opens]
        if missing:
            print("dongle.py log: never opened: %s" % " ".join(missing), file=sys.stderr)
            return 1
        return 0


def cmd_list(_args):
    devices = find(set(DEVICES.values()))
    width = max(len(name) for name in DEVICES)
    product_width = max(len(product) for product in DEVICES.values()) + 2
    for name, product in DEVICES.items():
        label = "%-*s  %-*s" % (width, name, product_width, '"%s"' % product)
        hits = [d for d in devices if d.product == product]
        if not hits:
            print("%s  absent" % label)
        for d in hits:
            ids = "location=%s serial=%s" % (d.location, d.serial or "-")
            if not d.ports:
                print("%s  on USB, no /dev/cu.* port  %s" % (label, ids))
                continue
            holders = port_holders(d)
            held = "held by " + ", ".join(holders) if holders else "port free"
            print("%s  %s  %s  %s" % (label, " ".join(d.ports), ids, held))
    volumes = sorted(v for v in glob.glob("/Volumes/*") if os.path.isfile(os.path.join(v, "INFO_UF2.TXT")))
    if VOLUME not in volumes:
        print("%s  %s" % (VOLUME, "exists without INFO_UF2.TXT" if os.path.exists(VOLUME) else "not mounted"))
    for volume in volumes:
        disk = mounted_disk(volume)
        owner = disk_owner(disk) if disk else None
        if owner is None:
            where = "no USB device found for it"
        else:
            where = "USB location %s: %s serial=%s" % (owner.location, owner.product or "(no product string)", owner.serial or "-")
        print("%s  UF2 bootloader on %s, %s" % (volume, disk or "(not a mount point)", where))
    try:
        running = subprocess.run(["pgrep", "-fl", FLASHERS], capture_output=True, text=True).stdout.strip()
    except OSError:
        running = "(pgrep unavailable)"
    print("flashers  %s" % (running.replace("\n", "; ") if running else "none running"))
    return 0


def cmd_port(args):
    product = DEVICES[args.device]
    hits = find({product})
    if not hits:
        raise Failure('no USB device named "%s"' % product)
    if len(hits) > 1:
        raise Failure('%d USB devices named "%s"; leave exactly one plugged in' % (len(hits), product))
    dev = hits[0]
    if not dev.ports:
        raise Failure('"%s" (serial %s) has no /dev/cu.* port' % (dev.product, dev.serial or "-"))
    if len(dev.ports) > 1:
        print("dongle.py: more than one port: %s" % " ".join(dev.ports), file=sys.stderr)
    print(dev.ports[0])
    return 0


def cmd_log(args):
    out = None
    if args.out is not None:
        for root in repository_roots():
            if is_inside(args.out, root):
                raise Failure("refusing --out %s: inside the repository %s (raw logs never go into a repository)"
                              % (args.out, root), 2)
        try:
            out = os.fdopen(os.open(args.out, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600), "a", encoding="utf-8")
        except OSError as e:
            raise Failure("cannot open --out %s: %s" % (args.out, e.strerror or e))
    try:
        return LogSession(list(dict.fromkeys(args.devices)), args.seconds, args.grep, args.raw, out).run()
    finally:
        if out is not None:
            out.close()


def cmd_image(args):
    # Messages leave out the path: flash-dongle.sh passes a snapshot and names
    # the image itself.
    try:
        with open(args.uf2, "rb") as f:
            data = f.read()
    except OSError as e:
        raise Failure("cannot read the image: %s" % (e.strerror or e), 2)
    payload = uf2_payload(data)
    if payload is None:
        raise Failure("not a UF2 file", 2)
    held = [name for name, product in DEVICES.items() if product.encode() in payload]
    if not held:
        raise Failure("the image holds no dongle's USB product string (%s): a halves image, the Prospector "
                      "Dongle's USB power-only one or another board's" % ", ".join('"%s"' % p for p in DEVICES.values()))
    if len(held) > 1:
        raise Failure("the image holds more than one dongle's USB product string: %s"
                      % ", ".join('"%s"' % DEVICES[name] for name in held))
    print(US.join([held[0], DEVICES[held[0]], hashlib.sha256(data).hexdigest()]))
    return 0


def cmd_find(args):
    for dev in find({DEVICES[args.device]}):
        print(US.join([dev.serial, str(dev.session), dev.location, " ".join(dev.ports)]))
    return 0


def cmd_owner(args):
    disk = mounted_disk(args.mountpoint)
    if disk is None:
        raise Failure("%s is not a mount point" % args.mountpoint)
    owner = disk_owner(disk)
    fields = [owner.product, owner.serial, str(owner.session), owner.location] if owner else ["", "", "", ""]
    print(US.join([disk] + fields))
    return 0


def seconds(text):
    try:
        value = float(text)
    except ValueError:
        value = math.nan
    if not (math.isfinite(value) and value > 0):
        raise argparse.ArgumentTypeError("a positive number of seconds, not %r" % text)
    return value


def regex(text):
    try:
        return re.compile(text)
    except re.error as e:
        raise argparse.ArgumentTypeError("not a regular expression: %s" % e)


def parser():
    names = ", ".join(DEVICES)
    p = argparse.ArgumentParser(
        prog="dongle.py",
        description="Find the Imprint Dongle and the Prospector Dongle on USB by their USB product "
                    "strings, and read their serial logs. Devices: %s." % names,
        epilog="Exit status: 0 ok, 1 device or runtime failure, 2 usage.",
    )
    sub = p.add_subparsers(dest="command", metavar="COMMAND")
    sub.required = True

    s = sub.add_parser("list", help="each dongle's port, USB location, serial and the processes holding "
                                    "its port; UF2 bootloader volumes; running flash scripts")
    s.set_defaults(func=cmd_list)

    s = sub.add_parser("port", help="print the dongle's /dev/cu.* port (exit 1 if it is absent)")
    s.add_argument("device", choices=DEVICES)
    s.set_defaults(func=cmd_port)

    s = sub.add_parser(
        "log", help="read the dongles' serial logs for a fixed time",
        description="Read the dongles' serial logs (a --logging image) at 115200 8N1, never another rate: "
                    "1200 baud reboots a dongle into its bootloader, 2400 is reserved. Each line is "
                    "'MM-DD HH:MM:SS.mmm DEVICE | text' for the device's output and "
                    "'MM-DD HH:MM:SS.mmm DEVICE # event' for the port opening, going away and coming "
                    "back: when a port goes away the reader polls for the dongle every 0.2 s and "
                    "reopens it, so a reader started before a flash catches the new image's boot log. "
                    "Prints its pid on stderr at the start; ends at the deadline with exit 0, or 1 when "
                    "a device never appeared.",
    )
    s.add_argument("devices", nargs="+", choices=DEVICES, metavar="DEVICE", help=names)
    s.add_argument("--seconds", type=seconds, required=True, metavar="N", help="stop after N seconds")
    s.add_argument("--grep", type=regex, metavar="RE", help="print only the device lines RE matches (re.search; (?i) for any case)")
    s.add_argument("--out", metavar="FILE", help="also append the printed lines to FILE (mode 0600), which must lie outside the repository")
    s.add_argument("--raw", action="store_true", help="keep the lines that carry keycodes, key positions or modifiers (dropped by default)")
    s.set_defaults(func=cmd_log)

    s = sub.add_parser("image", help="plumbing: DEVICE US PRODUCT US SHA256 of the dongle whose product string "
                                     "the UF2 payload holds (exit 1 for none or both, 2 for no UF2)")
    s.add_argument("uf2")
    s.set_defaults(func=cmd_image)

    s = sub.add_parser("find", help="plumbing: SERIAL US SESSION US LOCATION US PORTS, one line per USB "
                                    "device with the dongle's product string (none: no output)")
    s.add_argument("device", choices=DEVICES)
    s.set_defaults(func=cmd_find)

    s = sub.add_parser("owner", help="plumbing: DISK US PRODUCT US SERIAL US SESSION US LOCATION of the USB "
                                     "device behind the disk mounted at MOUNTPOINT (empty when none)")
    s.add_argument("mountpoint")
    s.set_defaults(func=cmd_owner)
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        return args.func(args)
    except Failure as e:
        print("dongle.py: %s" % e, file=sys.stderr)
        return e.status


if __name__ == "__main__":
    sys.exit(main())
