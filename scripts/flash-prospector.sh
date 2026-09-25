#!/usr/bin/env bash
# Flash the Prospector Dongle from the Mac alone, without a reset double-tap:
#   1. check the image carries the USB product string "Prospector Dongle", then
#      find the one USB device with that product string, its USB location and
#      its /dev/cu.* port (ioreg)
#   2. set that port to 1200 baud (stty) → the firmware reboots into the UF2
#      bootloader (CONFIG_PROSPECTOR_BOOTLOADER_ON_1200_BAUD)
#   3. wait for /Volumes/XIAO-SENSE and check that its disk belongs to the USB
#      device at the Prospector Dongle's USB location
#   4. cp -X the .uf2 → the volume disappears once the bootloader has taken the
#      image and rebooted
#   5. wait for "Prospector Dongle" to enumerate again
#
#   ./scripts/flash-prospector.sh              # firmware/prospector_scanner.uf2
#   ./scripts/flash-prospector.sh firmware/prospector_scanner-logging.uf2
#
# Only firmware/prospector_scanner*.uf2 whose payload holds the product string
# is accepted: any other image (the USB power-only one that predates the
# 1200 baud handler, a renamed imprint_dongle.uf2) never enumerates as
# "Prospector Dongle", so the next run could not find it. Re-enumeration shows
# that such an image booted, not which one: the display is the user's check.
# The first image with the handler goes on by double-tap + cp -X (README).
#
# Refuses to start while /Volumes/XIAO-SENSE is mounted or while
# flash-watch.sh / flash-reset.sh run (both dongles mount as XIAO-SENSE, and
# those scripts copy imprint_dongle.uf2 onto any XIAO-SENSE mount). Right
# before the copy it checks for those scripts again, and step 3's identity
# check stands in for the mount check.
#
# Exit status: 0 image copied, bootloader volume released and a
# "Prospector Dongle" back on USB / 1 failed / 2 usage.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 1

# Contract with config/prospector_scanner.conf (CONFIG_USB_DEVICE_PRODUCT).
PRODUCT="Prospector Dongle"
VOL="/Volumes/XIAO-SENSE"
STTY_TIMEOUT_S=5
BOOT_TIMEOUT_S=20
COPY_TIMEOUT_S=120
WRITE_TIMEOUT_S=120
ENUM_TIMEOUT_S=30
STRANDED="The Prospector Dongle may be left in its bootloader: finish it by hand (double-tap + cp -X, README) or unplug it before flash-watch.sh or flash-reset.sh runs."

ts() { date +%H:%M:%S; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR $*" >&2; exit 1; }
die_touched() { die "$* $STRANDED"; }
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1fs", (b - a) / 1000 }'; }

# ioreg lookups, one line per hit, fields split by US (0x1f; a tab would
# collapse empty fields under IFS). A USB device prints as
#   product US serial US sessionID US locationID
# with product and serial the descriptor strings (kUSB*String; "USB Product
# Name" is macOS's sanitised copy, "-" becomes "_").
#   product NAME  every USB device whose product string is NAME (IOUSB plane:
#                 no class subtrees, so it stays fast behind USB disks)
#   ports SESSION the /dev/cu.* paths whose nearest USB device ancestor has
#                 that sessionID, space separated
#   disk BSDNAME  the USB device that is the nearest ancestor of that IOMedia
# -t prints each match with its ancestors, so the nearest IOUSBHostDevice on
# the path is the device the port or disk belongs to.
ioq() {
  python3 - "$1" "$2" <<'PY'
import plistlib, subprocess, sys

def ioreg(*args):
    raw = subprocess.run(["ioreg", "-a", *args], capture_output=True, check=True).stdout
    roots = plistlib.loads(raw) if raw.strip() else []
    return roots if isinstance(roots, list) else [roots]

def children(node):
    kids = node.get("IORegistryEntryChildren", [])
    return [kids] if isinstance(kids, dict) else kids  # -t: a lone child is a dict

def walk(node, usb=None):
    if node.get("IOObjectClass") == "IOUSBHostDevice":
        usb = node
    yield node, usb
    for kid in children(node):
        yield from walk(kid, usb)

def device(dev):
    return "\x1f".join([str(dev.get("kUSBProductString", "")),
                        str(dev.get("kUSBSerialNumberString", "")),
                        str(dev.get("sessionID", "")),
                        "0x%08x" % dev.get("locationID", 0)])

cmd, arg = sys.argv[1], sys.argv[2]
lines = []
if cmd == "product":
    for root in ioreg("-p", "IOUSB", "-l"):
        for node, usb in walk(root):
            if node is usb and node.get("kUSBProductString") == arg:
                lines.append(device(node))
elif cmd == "ports":
    ports = set()
    for root in ioreg("-r", "-t", "-c", "IOSerialBSDClient", "-l"):
        for node, usb in walk(root):
            if "IOCalloutDevice" in node and usb is not None and str(usb.get("sessionID")) == arg:
                ports.add(node["IOCalloutDevice"])
    if ports:
        lines.append(" ".join(sorted(ports)))
elif cmd == "disk":
    for root in ioreg("-r", "-t", "-c", "IOMedia", "-l"):
        for node, usb in walk(root):
            if node.get("BSD Name") == arg and usb is not None:
                lines.append(device(usb))
else:
    sys.exit("ioq: unknown query " + cmd)
for line in dict.fromkeys(lines):
    print(line)
PY
}

# Exit 0 when the UF2's payload holds $2, 1 when not, 2 when $1 is no UF2.
# Payloads are joined in target-address order, so a string that straddles two
# blocks still matches.
uf2_holds() {
  python3 - "$1" "$2" <<'PY'
import struct, sys

data = open(sys.argv[1], "rb").read()
if not data or len(data) % 512:
    sys.exit(2)
chunks = {}
for off in range(0, len(data), 512):
    block = data[off:off + 512]
    magic0, magic1, _flags, addr, size = struct.unpack_from("<5I", block)
    (magic_end,) = struct.unpack_from("<I", block, 508)
    if (magic0, magic1, magic_end) != (0x0A324655, 0x9E5D5157, 0x0AB16F30) or size > 476:
        sys.exit(2)
    chunks[addr] = block[32:32 + size]
image = b"".join(chunks[a] for a in sorted(chunks))
sys.exit(0 if sys.argv[2].encode() in image else 1)
PY
}

# Runs "$@" for at most $1 s with its stderr in file $2. BOUNDED_RC gets the
# exit status, or 124 once it had to be killed. A process that survives SIGKILL
# (a close on a vanished USB volume can sleep uninterruptibly) is left behind,
# never waited on.
run_bounded() {
  local limit_ms=$(($1 * 1000)) err="$2" pid start
  shift 2
  "$@" 2>"$err" &
  pid=$!
  start=$(now_ms)
  while kill -0 "$pid" 2>/dev/null; do
    if [ $(($(now_ms) - start)) -ge "$limit_ms" ]; then
      kill -9 "$pid" 2>/dev/null
      sleep 1
      kill -0 "$pid" 2>/dev/null || wait "$pid" 2>/dev/null
      BOUNDED_RC=124
      return 0
    fi
    sleep 0.2
  done
  wait "$pid"
  BOUNDED_RC=$?
}

# The /dev node mounted exactly at $1 (diskN or diskNsM), empty when $1 is not
# a mount point (df then names the enclosing file system).
mounted_disk() {
  df -P "$1" 2>/dev/null | awk -v m="$1" 'NR == 2 && $NF == m { sub(/^\/dev\//, "", $1); print $1 }'
}

flashers_running() { pgrep -fl 'flash-(watch|reset|impl)\.sh'; }

UF2_ARG=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *)
      [ -z "$UF2_ARG" ] || { echo "at most one .uf2 path" >&2; exit 2; }
      UF2_ARG="$arg" ;;
  esac
done

# Resolved against the caller's cwd, then pinned to <repo>/firmware and to a
# regular file, so that neither ../ nor a symlink can smuggle in
# imprint_dongle.uf2.
UF2_ARG="${UF2_ARG:-$REPO/firmware/prospector_scanner.uf2}"
UF2_DIR="$(cd "$(dirname "$UF2_ARG")" 2>/dev/null && pwd -P)" || UF2_DIR=""
UF2_BASE="$(basename "$UF2_ARG")"
case "$UF2_BASE" in
  prospector_scanner*.uf2) ;;
  *) echo "refusing $UF2_ARG: only firmware/prospector_scanner*.uf2 goes onto the Prospector Dongle" >&2; exit 2 ;;
esac
[ "$UF2_DIR" = "$REPO/firmware" ] \
  || { echo "refusing $UF2_ARG: not in $REPO/firmware" >&2; exit 2; }
UF2="$UF2_DIR/$UF2_BASE"
[ ! -L "$UF2" ] || { echo "refusing $UF2_ARG: a symlink" >&2; exit 2; }
[ -f "$UF2" ] || die "$UF2 not found (build it: ./scripts/build-zmk.sh prospector_scanner)"

[ "$(uname -s)" = Darwin ] || die "macOS only (ioreg, stty -f, /Volumes)"
for tool in ioreg stty df pgrep python3; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

uf2_holds "$UF2" "$PRODUCT"
case $? in
  0) ;;
  1) echo "refusing $UF2_ARG: its image has no \"$PRODUCT\" USB product string, so it would not enumerate for the next flash (a USB power-only build or another device's image). Rebuild: ./scripts/build-zmk.sh prospector_scanner" >&2; exit 2 ;;
  *) echo "refusing $UF2_ARG: not a UF2 file" >&2; exit 2 ;;
esac

if [ -e "$VOL" ]; then
  die "$VOL is already mounted: a dongle (the Imprint Dongle, or the Prospector Dongle after an earlier failed run) is in its bootloader, so the copy target is ambiguous. Finish or eject that one first."
fi
if running="$(flashers_running)"; then
  die "flash-watch.sh / flash-reset.sh is running (it copies imprint_dongle.uf2 onto any XIAO-SENSE mount):
$running"
fi

ERR="$(mktemp -t flash-prospector)" || die "mktemp failed"
trap 'rm -f "$ERR"' EXIT

devices="$(ioq product "$PRODUCT")" || die "ioreg query failed"
count=$(printf '%s' "$devices" | grep -c .)
if [ "$count" -eq 0 ]; then
  die "no USB device named \"$PRODUCT\". The USB power-only image that preceded the 1200 baud handler does not enumerate, nor does anything behind a charge-only cable: double-tap reset and cp -X by hand (README)."
fi
[ "$count" -eq 1 ] || die "$count USB devices named \"$PRODUCT\"; leave exactly one plugged in:
$(printf '%s\n' "$devices" | tr '\037' ' ')"
IFS=$'\x1f' read -r _ SERIAL SESSION LOCATION <<<"$devices"
PORTS="$(ioq ports "$SESSION")" || die "ioreg query failed"
PORT="${PORTS%% *}"
[ -n "$PORT" ] || die "\"$PRODUCT\" (serial $SERIAL) has no /dev/cu.* port"
say "FOUND $PRODUCT serial=$SERIAL location=$LOCATION port=$PORT"
[ "$PORT" = "$PORTS" ] || say "      more than one port ($PORTS); the handler listens on all of them"
say "IMAGE $UF2"

# stty opens with O_NONBLOCK; the device may vanish mid-call and fail it, so
# its exit status is logged, not judged.
t0=$(now_ms)
say "TOUCH stty -f $PORT 1200"
run_bounded "$STTY_TIMEOUT_S" "$ERR" stty -f "$PORT" 1200
say "      stty exit=$BOUNDED_RC$([ "$BOUNDED_RC" -ne 124 ] || echo " (killed after ${STTY_TIMEOUT_S}s)") $(tr '\n' ' ' <"$ERR")"

deadline=$((t0 + BOOT_TIMEOUT_S * 1000))
until [ -f "$VOL/INFO_UF2.TXT" ]; do
  [ "$(now_ms)" -lt "$deadline" ] \
    || die_touched "no $VOL within ${BOOT_TIMEOUT_S}s: the firmware lacks the handler or the host sent no 1200 baud line coding."
  sleep 0.2
done
t_boot=$(now_ms)
say "BOOTLOADER $VOL after $(secs "$t0" "$t_boot")"
# shellcheck disable=SC2001  # indenting every line is clearest with sed
sed 's/^/           /' "$VOL/INFO_UF2.TXT"

# Identity, not presence: the Prospector Dongle having left USB does not make
# $VOL its volume (the Imprint Dongle may hold XIAO-SENSE while the Prospector
# Dongle's mounts under a suffixed name). Its bootloader enumerates on the same
# USB port, so the disk behind $VOL must sit under the device at LOCATION.
disk="$(mounted_disk "$VOL")"
[ -n "$disk" ] || die_touched "$VOL is not a mount point. Nothing copied."
owner="$(ioq disk "$disk")" || die_touched "ioreg query failed. Nothing copied."
IFS=$'\x1f' read -r OWNER_PRODUCT OWNER_SERIAL _ OWNER_LOCATION <<<"$owner"
say "      $VOL is $disk on USB location ${OWNER_LOCATION:-(none)}: ${OWNER_PRODUCT:-(no product string)} serial=${OWNER_SERIAL:-(none)}"
[ -n "$OWNER_LOCATION" ] && [ "$OWNER_LOCATION" = "$LOCATION" ] \
  || die_touched "$VOL is not on the Prospector Dongle's USB location ($LOCATION): another board's bootloader holds it. Nothing copied."

if running="$(flashers_running)"; then
  die_touched "flash-watch.sh / flash-reset.sh started meanwhile. Nothing copied. Stop it first:
$running
"
fi
[ -f "$VOL/INFO_UF2.TXT" ] || die_touched "$VOL went away before the copy. Nothing copied."

say "COPY $UF2_BASE → $VOL"
run_bounded "$COPY_TIMEOUT_S" "$ERR" cp -X "$UF2" "$VOL/"
cp_rc=$BOUNDED_RC
cp_err="$(tr '\n' ' ' <"$ERR")"
case "$cp_rc" in
  0) say "      cp exit=0" ;;
  124) die_touched "cp -X still running after ${COPY_TIMEOUT_S}s, killed." ;;
  *)
    case "$cp_err" in
      *"Input/output error"*|*"Device not configured"*)
        say "      cp exit=$cp_rc: $cp_err(the bootloader rebooting under the copy)" ;;
      *) die_touched "cp -X failed (exit $cp_rc): $cp_err" ;;
    esac ;;
esac

deadline=$(($(now_ms) + WRITE_TIMEOUT_S * 1000))
while [ -f "$VOL/INFO_UF2.TXT" ]; do
  [ "$(now_ms)" -lt "$deadline" ] \
    || die_touched "$VOL still mounted ${WRITE_TIMEOUT_S}s after the copy: the bootloader did not take the image."
  sleep 0.2
done
t_written=$(now_ms)
say "WRITTEN $VOL gone after $(secs "$t0" "$t_written")"

deadline=$((t_written + ENUM_TIMEOUT_S * 1000))
while :; do
  back="$(ioq product "$PRODUCT")" || die "ioreg query failed"
  [ -z "$back" ] || break
  [ "$(now_ms)" -lt "$deadline" ] \
    || die_touched "\"$PRODUCT\" did not enumerate within ${ENUM_TIMEOUT_S}s of the write: the image may not boot. Check the display."
  sleep 0.5
done
t_back=$(now_ms)
IFS=$'\x1f' read -r _ BACK_SERIAL BACK_SESSION BACK_LOCATION <<<"$back"
say "BACK $PRODUCT serial=$BACK_SERIAL location=$BACK_LOCATION after $(secs "$t0" "$t_back")"
[ "$BACK_SERIAL" = "$SERIAL" ] || say "      WARN serial differs from before the touch ($SERIAL)"
[ "$BACK_LOCATION" = "$LOCATION" ] || say "      WARN location differs from before the touch ($LOCATION)"
[ "$BACK_SESSION" != "$SESSION" ] || say "      WARN same registry session as before the touch"
say "DONE bootloader $(secs "$t0" "$t_boot") / written $(secs "$t0" "$t_written") / back $(secs "$t0" "$t_back"). Check the display."
