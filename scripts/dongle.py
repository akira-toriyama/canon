#!/usr/bin/env python3
# Which USB device is which dongle, a serial log reader that follows them, and
# a PNG of the Prospector Dongle's screen.
#
# The one place that identifies the dongles on USB: flash-dongle.sh leaves the
# product strings and the ioreg and df lookups to the plumbing subcommands and
# parses their US-separated fields, so those fields are a contract with it.
#
# Identity is the USB product string alone. Both dongles (and the ist dongle
# of zmk-hid-host) carry ZMK's default VID/PID 0x1D50/0x615E, and a
# /dev/cu.usbmodem* name is derived from the USB location (0x02112000 ->
# usbmodem211201): never identify a dongle by either.
#
# The rate of a port is a command to the firmware, whichever program sets it,
# acted on when the rate changes: 1200 reboots either dongle into its UF2
# bootloader (zmk-beacon's CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD), and 2400
# makes the Prospector Dongle send its screen (CONFIG_BEACON_SCREEN_DUMP).
# `log` sets 115200 8N1 and no other rate; `shot` sets 2400 and then 115200
# again, never 1200. Neither sets TIOCEXCL: flash-dongle.sh's stty must still
# open a port that a reader holds, and a log reader then follows the dongle
# through the bootloader into the new image's boot log.
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
import tempfile
import termios
import time
import zlib
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

# The screen dump's records (zmk-beacon src/screen_dump.c, whose header is the
# contract: change both together and bump DUMP_VERSION). Integers are
# little-endian.
#   start  tag version:u8 format:u8 width:u16 height:u16
#   band   tag x1:u16 y1:u16 x2:u16 y2:u16, then the band's RGB565 pixels
#   end    tag bands:u16 crc32:u32 (zlib's crc32 of every band's pixels)
#   error  tag reason:u8, in place of the rest
DUMP_BAUD = termios.B2400  # BEACON_SCREEN_DUMP_BAUD
DUMP_VERSION = 1
TAG_START, TAG_BAND, TAG_END, TAG_ERROR = b"\xa5SCR", b"\xa5BND", b"\xa5END", b"\xa5ERR"
DUMP_FORMATS = {1: ">", 2: "<"}  # RGB565 high byte first / low byte first
DUMP_ERRORS = {
    1: "the firmware has no display",
    2: "the display's color format is not RGB565",
    3: "the display did not refresh within 2 s",
    4: "LVGL's draw buffer did not match the band it flushed",
}
# Older output ends once the port stays quiet this long (log lines come far
# apart), and the wait for it ends in any case after DRAIN_LIMIT_S.
DRAIN_QUIET_S = 0.2
DRAIN_LIMIT_S = 3.0
FIVE_BITS = bytes((v << 3) | (v >> 2) for v in range(32))
SIX_BITS = bytes((v << 2) | (v >> 4) for v in range(64))

# Lines that carry a keycode, a HID usage, a key position, modifier state or a
# key's press and release. From the LOG_DBG calls of ZMK main 5b51501f app/src
# (hid_listener, hid, keymap, behaviors, combo, split central, wpm) and canon's
# vkey patch. Debug lines lead with their function's name
# (CONFIG_LOG_FUNC_NAME_PREFIX_DBG, on by default), so hold-tap lines such as
# "decide_hold_tap: 23 decided tap" match by it; the message words cover a
# build without that prefix. Two more sources carry keystrokes without those
# words: behavior_queue.c's "Invoking <behavior>: <param1> <param2>", logged
# for every macro step (canon's capitals and en_* digits and symbols are
# macros), and the split central's LOG_HEXDUMP_DBG of position_state
# (split/bluetooth/central.c), whose data rows are the bitmap of pressed key
# positions. A bare "invoking" would also drop central.c's "... before
# invoking peripheral behavior" error. Kept on purpose: zmk-beacon's keystroke
# counts and the split discovery line "Found position state characteristic".
KEY_EVENT = re.compile(
    r"keycode|usage|position|modifier|implicit.?mods|explicit.?mods"
    r"|hold.?tap|retro.?tap|tap.?dance|sticky.?key|caps.?word|combo|macro"
    r"|mouse|button|pressed|released|decision moment|bubbl|capturing"
    r"|behavior.?queue|invoking \S+: 0x",
    re.I,
)
KEY_EVENT_KEPT = re.compile(r"characteristic", re.I)
# A LOG_HEXDUMP_* data row (zephyr log_output.c hexdump_line_print): an
# indented "xx xx ... |ascii" with no words for KEY_EVENT to match.
HEXDUMP_ROW = re.compile(r"^\s+(?:[0-9a-f]{2} +){1,16}.*\|")

# ANSI escape sequences (CSI, and two-byte Fe) and the ASCII controls but tab
# and newline.
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
    return [kids] if isinstance(kids, dict) else kids  # -t: an ancestor's child on the path is a dict


def walk(node, usb=None):
    """Each node at or below node, with the nearest IOUSBHostDevice at or above it."""
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
    Product Name" can be macOS's sanitised copy, with "-" as "_"). The IOUSB
    plane has no class subtrees, so it stays fast behind USB disks. Serial
    clients come with their ancestors (-t), so the nearest IOUSBHostDevice
    above a port is the device it belongs to.
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

    Joined, a string that straddles two blocks still matches. Raises Failure
    for an incomplete UF2: every block must carry the file's block count and
    the block numbers 0..N-1 in order. Bootloader 0.6.1 writes each block over
    the app as it arrives and resets only once numBlocks blocks came in, so a
    cut-short copy or download would leave the dongle in its bootloader with a
    half-written app.
    """
    if not data or len(data) % 512:
        return None
    total = len(data) // 512
    chunks = {}
    for i in range(total):
        off = i * 512
        magic0, magic1, _flags, addr, size, block_no, num_blocks = struct.unpack_from("<7I", data, off)
        (magic_end,) = struct.unpack_from("<I", data, off + 508)
        if (magic0, magic1, magic_end) != (0x0A324655, 0x9E5D5157, 0x0AB16F30) or size > 476:
            return None
        if (block_no, num_blocks) != (i, total):
            raise Failure("an incomplete UF2: the file holds %d blocks, but block %d says %d of %d "
                          "(a cut-short copy or download)" % (total, i, block_no, num_blocks), 2)
        chunks[addr] = data[off + 32:off + 32 + size]
    return b"".join(chunks[a] for a in sorted(chunks))


def clean(raw):
    return ESCAPES.sub("", raw.decode("utf-8", "replace")).rstrip()


def split_lines(buf):
    """The complete lines in buf and the unterminated rest."""
    *lines, rest = buf.split(b"\n")
    return lines, rest


def is_key_event(line):
    if HEXDUMP_ROW.match(line):
        return True
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


def work_tree(path):
    """The top of the git work tree path lies in, else None. git answers from
    the nearest existing directory above path (--out names a file not yet
    there), without the GIT_* variables that would point it elsewhere."""
    d = os.path.dirname(os.path.realpath(path))
    while not os.path.isdir(d):
        d = os.path.dirname(d)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        top = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, env=env).stdout.strip()
    except OSError:
        return None
    return top or None


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


def the_dongle(device):
    """The one USB device with the dongle's product string; it must have a port."""
    product = DEVICES[device]
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
    return dev


def refuse_inside_repository(path, why):
    """Any git work tree, not only this checkout: canon's other worktrees and
    the zmk-beacon checkouts are public repositories too. This checkout is
    refused without git's help as well."""
    top = work_tree(path) or (REPO if is_inside(path, REPO) else None)
    if top is not None:
        raise Failure("refusing --out %s: inside the git work tree %s (%s)" % (path, top, why), 2)


def cmd_port(args):
    print(the_dongle(args.device).ports[0])
    return 0


def cmd_log(args):
    out = None
    if args.out is not None:
        refuse_inside_repository(args.out, "raw logs never go into a repository")
        try:
            out = os.fdopen(os.open(args.out, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600), "a", encoding="utf-8")
        except OSError as e:
            raise Failure("cannot open --out %s: %s" % (args.out, e.strerror or e))
    try:
        return LogSession(list(dict.fromkeys(args.devices)), args.seconds, args.grep, args.raw, out).run()
    finally:
        if out is not None:
            out.close()


class Dump:
    """A screen dump, parsed from the port's bytes as they arrive."""

    def __init__(self):
        self.buf = bytearray()
        self.skipped = 0  # bytes ahead of the start record: older output
        self.width = self.height = self.order = None
        self.pixels = self.covered = None
        self.bands = 0
        self.crc = 0
        self.done = False

    def feed(self, data):
        self.buf += data
        while not self.done and self.step():
            pass

    def step(self):
        """Takes one record off buf; False when it needs more bytes first or
        has taken the end record."""
        if self.width is None:
            return self.start()
        tag = bytes(self.buf[:4])
        if len(tag) < 4:
            return False
        if tag == TAG_BAND:
            return self.band()
        if tag == TAG_END:
            return self.end()
        if tag == TAG_ERROR:
            return self.error()
        raise Failure("the dump broke off after %d bands: %r is no record tag (bytes lost, or other output "
                      "mixed in)" % (self.bands, tag))

    def start(self):
        hits = [i for i in (self.buf.find(TAG_START), self.buf.find(TAG_ERROR)) if i >= 0]
        if not hits:
            drop = max(0, len(self.buf) - (len(TAG_START) - 1))  # keep a tag cut by the read
            self.skipped += drop
            del self.buf[:drop]
            return False
        self.skipped += min(hits)
        del self.buf[:min(hits)]
        if self.buf.startswith(TAG_ERROR):
            return self.error()
        if len(self.buf) < 10:
            return False
        version, fmt, width, height = struct.unpack_from("<BBHH", self.buf, 4)
        if version != DUMP_VERSION:
            raise Failure("a version %d screen dump, and dongle.py reads version %d: canon and its zmk-beacon "
                          "pin disagree with the image" % (version, DUMP_VERSION))
        if fmt not in DUMP_FORMATS or width == 0 or height == 0:
            raise Failure("a malformed start record: format %d, %dx%d" % (fmt, width, height))
        del self.buf[:10]
        self.width, self.height, self.order = width, height, DUMP_FORMATS[fmt]
        self.pixels = bytearray(width * height * 2)
        self.covered = bytearray(width * height)
        return True

    def band(self):
        if len(self.buf) < 12:
            return False
        x1, y1, x2, y2 = struct.unpack_from("<4H", self.buf, 4)
        if not (x1 <= x2 < self.width and y1 <= y2 < self.height):
            raise Failure("band %d, (%d,%d)-(%d,%d), lies outside the %dx%d screen"
                          % (self.bands + 1, x1, y1, x2, y2, self.width, self.height))
        w, h = x2 - x1 + 1, y2 - y1 + 1
        end = 12 + w * h * 2
        if len(self.buf) < end:
            return False
        data = bytes(self.buf[12:end])
        del self.buf[:end]
        self.crc = zlib.crc32(data, self.crc)
        for row in range(h):
            at = (y1 + row) * self.width + x1
            if any(self.covered[at:at + w]):
                raise Failure("band %d overlaps an earlier one in row %d" % (self.bands + 1, y1 + row))
            self.covered[at:at + w] = b"\x01" * w
            self.pixels[2 * at:2 * (at + w)] = data[2 * w * row:2 * w * (row + 1)]
        self.bands += 1
        return True

    def end(self):
        if len(self.buf) < 10:
            return False
        bands, crc = struct.unpack_from("<HI", self.buf, 4)
        del self.buf[:10]
        if bands != self.bands:
            raise Failure("the end record counts %d bands, %d arrived" % (bands, self.bands))
        if crc != self.crc:
            raise Failure("CRC-32 %08x from the dongle, %08x over the bands read: bytes were lost or altered"
                          % (crc, self.crc))
        missing = self.covered.count(0)
        if missing:
            raise Failure("the bands left %d of the %d pixels uncovered" % (missing, self.width * self.height))
        self.done = True
        return False

    def error(self):
        if len(self.buf) < 5:
            return False
        reason = self.buf[4]
        raise Failure("the Prospector Dongle gave up the dump: %s (reason %d)"
                      % (DUMP_ERRORS.get(reason, "a reason this dongle.py does not know"), reason))


def png(dump):
    """The dump as an 8-bit RGB PNG, RGB565 widened by bit replication."""
    values = struct.unpack("%s%dH" % (dump.order, dump.width * dump.height), dump.pixels)
    raw = bytearray()
    row = bytearray(1 + 3 * dump.width)  # filter byte 0: none
    for y in range(dump.height):
        for x, v in enumerate(values[y * dump.width:(y + 1) * dump.width]):
            at = 1 + 3 * x
            row[at] = FIVE_BITS[v >> 11]
            row[at + 1] = SIX_BITS[(v >> 5) & 0x3F]
            row[at + 2] = FIVE_BITS[v & 0x1F]
        raw += row

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", dump.width, dump.height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def set_speed(fd, speed):
    if speed == termios.B1200:
        raise Failure("refusing to set 1200 baud: it reboots the dongle into its UF2 bootloader")
    attrs = termios.tcgetattr(fd)
    attrs[4] = attrs[5] = speed
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def read_some(fd, port, timeout):
    """The bytes that arrive within timeout seconds (b"" for none)."""
    ready, _, _ = select.select([fd], [], [], max(timeout, 0.0))
    if not ready:
        return b""
    try:
        chunk = os.read(fd, 65536)
    except (BlockingIOError, InterruptedError):
        return b""
    except OSError as e:
        raise Failure("lost %s: %s" % (port, e.strerror or e))
    if not chunk:
        raise Failure("lost %s: end of file" % port)
    return chunk


def drain(fd, port):
    """Reads away the port's older output (log lines, the tail of an abandoned
    dump), so that a start tag in it cannot pass for the new dump's."""
    drained = 0
    limit = time.monotonic() + DRAIN_LIMIT_S
    while True:
        wait = min(DRAIN_QUIET_S, limit - time.monotonic())
        if wait <= 0:
            return drained
        chunk = read_some(fd, port, wait)
        if not chunk:
            return drained
        drained += len(chunk)


def read_dump(fd, port, seconds):
    dump = Dump()
    deadline = time.monotonic() + seconds
    while not dump.done:
        left = deadline - time.monotonic()
        if left <= 0:
            if dump.width is None:
                raise Failure("no screen dump from the Prospector Dongle within %g s: an image without "
                              "zmk-beacon's CONFIG_BEACON_SCREEN_DUMP ignores 2400 baud" % seconds)
            raise Failure("the dump stopped after %d bands (%g s)" % (dump.bands, seconds))
        dump.feed(read_some(fd, port, min(left, 0.5)))
    return dump


def cmd_shot(args):
    path = args.out or os.path.join(
        tempfile.gettempdir(), datetime.datetime.now().strftime("prospector-%Y%m%d-%H%M%S-%f.png"))
    refuse_inside_repository(path, "the screen of a sprite build shows its personal GIF")
    dev = the_dongle("prospector")
    port = dev.ports[0]
    holders = port_holders(dev)
    if holders:
        raise Failure("%s is held by %s: two readers would split the dump between them; stop the other first"
                      % (port, ", ".join(holders)))
    started = time.monotonic()
    try:
        fd = open_port(port)
    except (OSError, termios.error) as e:  # termios.error is no OSError
        raise Failure("cannot open %s: %s" % (port, e.args[-1]))
    try:
        skipped = drain(fd, port)
        set_speed(fd, DUMP_BAUD)
        dump = read_dump(fd, port, args.seconds)
    except termios.error as e:
        raise Failure("cannot set %s to 2400 baud: %s" % (port, e.args[-1]))
    finally:
        try:
            set_speed(fd, termios.B115200)
        except (OSError, termios.error):
            pass  # the port is gone: the dongle left USB
        os.close(fd)
    try:
        with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as f:
            f.write(png(dump))
    except OSError as e:
        raise Failure("cannot write %s: %s" % (path, e.strerror or e))
    print("dongle.py shot: %dx%d in %d bands, CRC-32 ok, %.1f s; skipped %d bytes of older output"
          % (dump.width, dump.height, dump.bands, time.monotonic() - started, skipped + dump.skipped),
          file=sys.stderr)
    print(os.path.abspath(path))
    return 0


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


def cmd_at(args):
    try:
        location = int(args.location, 16)
    except ValueError:
        raise Failure("not a USB location: %r (0x02114000, as find prints it)" % args.location, 2)
    for root in ioreg("-p", "IOUSB", "-l"):
        for node, usb in walk(root):
            if node is usb and node.get("locationID") == location:
                dev = usb_device(node)
                print(US.join([dev.product, dev.serial, str(dev.session)]))
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
                    "strings, read their serial logs, and take a PNG of the Prospector Dongle's screen. "
                    "Devices: %s." % names,
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
                    "1200 baud reboots a dongle into its bootloader, and 2400 makes the Prospector Dongle "
                    "send its screen (shot). Each line is "
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
    s.add_argument("--out", metavar="FILE", help="also append the printed lines to FILE (mode 0600), which must lie outside any git work tree")
    s.add_argument("--raw", action="store_true", help="keep the lines that carry keycodes, key positions or modifiers (dropped by default)")
    s.set_defaults(func=cmd_log)

    s = sub.add_parser(
        "shot", help="write a PNG of the Prospector Dongle's screen and print its path",
        description="Set the Prospector Dongle's port to 2400 baud, on which its firmware (zmk-beacon "
                    "CONFIG_BEACON_SCREEN_DUMP) renders the screen once more and sends it; check the bands "
                    "against their CRC-32 and write an RGB PNG (mode 0600 when created). The port goes back "
                    "to 115200 afterwards and never to 1200, which reboots the dongle into its bootloader. "
                    "Refuses while another process holds the port: two readers would split the dump. "
                    "Prints the PNG's path on stdout and a summary on stderr.",
    )
    s.add_argument("--out", metavar="FILE", help="the PNG to write, outside any git work tree "
                                                 "(default: prospector-<date>-<time>-<microseconds>.png in the temporary directory)")
    s.add_argument("--seconds", type=seconds, default=10.0, metavar="N", help="give up after N seconds (default 10)")
    s.set_defaults(func=cmd_shot)

    s = sub.add_parser("image", help="plumbing: DEVICE US PRODUCT US SHA256 of the dongle whose product string "
                                     "the UF2 payload holds (exit 1 for none or both, 2 for no UF2 or an incomplete one)")
    s.add_argument("uf2")
    s.set_defaults(func=cmd_image)

    s = sub.add_parser("find", help="plumbing: SERIAL US SESSION US LOCATION US PORTS, one line per USB "
                                    "device with the dongle's product string (none: no output)")
    s.add_argument("device", choices=DEVICES)
    s.set_defaults(func=cmd_find)

    s = sub.add_parser("at", help="plumbing: PRODUCT US SERIAL US SESSION of the USB device at LOCATION, "
                                  "whatever it is (a dongle's bootloader too; none: no output)")
    s.add_argument("location")
    s.set_defaults(func=cmd_at)

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
    except KeyboardInterrupt:  # log handles SIGINT itself; shot's finally has reset the port
        print("dongle.py: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
