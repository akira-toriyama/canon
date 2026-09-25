#!/usr/bin/env bash
# Flash the Prospector Dongle from the Mac alone, without a reset double-tap:
#   1. find the USB device whose product string is "Prospector Dongle" and its
#      /dev/cu.* port (ioreg)
#   2. set that port to 1200 baud (stty) → the firmware reboots into the UF2
#      bootloader (CONFIG_PROSPECTOR_BOOTLOADER_ON_1200_BAUD)
#   3. wait for /Volumes/XIAO-SENSE and check the Prospector Dongle left the bus
#   4. cp -X the .uf2 → the volume disappears once the bootloader has taken the
#      image and rebooted (that, not cp's exit status, is the verdict)
#   5. wait for "Prospector Dongle" to enumerate again
#
#   ./scripts/flash-prospector.sh              # firmware/prospector_scanner.uf2
#   ./scripts/flash-prospector.sh firmware/prospector_scanner-logging.uf2
#
# Only firmware/prospector_scanner*.uf2 is accepted. Re-enumeration proves that
# an image with the 1200 baud handler booted, not which image: the display is
# the user's check. The USB power-only image that preceded the handler never
# enumerates, so the first image with the handler goes on by double-tap +
# cp -X (README).
#
# Refuses to start while /Volumes/XIAO-SENSE is mounted (some XIAO is already in
# its bootloader, so the copy target would be ambiguous) or while
# flash-watch.sh / flash-reset.sh run: both dongles mount as XIAO-SENSE and
# those scripts copy imprint_dongle.uf2 onto any XIAO-SENSE mount.
#
# Exit status: 0 flashed and back on USB / 1 failed / 2 usage.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 1

# Contract with config/prospector_scanner.conf (CONFIG_USB_DEVICE_PRODUCT).
PRODUCT="Prospector Dongle"
VOL="/Volumes/XIAO-SENSE"
BOOT_TIMEOUT_S=20
GONE_TIMEOUT_S=3
WRITE_TIMEOUT_S=120
ENUM_TIMEOUT_S=30

ts() { date +%H:%M:%S; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR $*" >&2; exit 1; }
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1fs", (b - a) / 1000 }'; }

# One line per USB device whose "USB Product Name" (product) or
# "USB Serial Number" (serial) equals $2, fields split by US (0x1f; a tab
# would collapse empty fields under IFS):
#   product US serial US sessionID US callout paths (space separated)
# ioreg -r lists a device under a hub both as its own root and inside the hub,
# hence the sessionID dedup; a nested device's ports belong to that device.
usb_devices() {
  python3 - "$1" "$2" <<'PY'
import plistlib, subprocess, sys

field = {"product": "USB Product Name", "serial": "USB Serial Number"}[sys.argv[1]]
want = sys.argv[2]
raw = subprocess.run(["ioreg", "-a", "-r", "-c", "IOUSBHostDevice", "-l"],
                     capture_output=True, check=True).stdout
roots = plistlib.loads(raw) if raw.strip() else []
if isinstance(roots, dict):
    roots = [roots]

def callouts(node, top):
    if not top and node.get("IOObjectClass") == "IOUSBHostDevice":
        return []
    found = [node["IOCalloutDevice"]] if "IOCalloutDevice" in node else []
    for child in node.get("IORegistryEntryChildren", []):
        found += callouts(child, False)
    return found

seen = set()
def visit(node):
    if node.get("IOObjectClass") == "IOUSBHostDevice" and node.get("sessionID") not in seen:
        seen.add(node.get("sessionID"))
        if node.get(field) == want:
            print("\x1f".join([str(node.get("USB Product Name", "")),
                             str(node.get("USB Serial Number", "")),
                             str(node.get("sessionID", "")),
                             " ".join(sorted(callouts(node, True)))]))
    for child in node.get("IORegistryEntryChildren", []):
        visit(child)

for root in roots:
    visit(root)
PY
}

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
for tool in ioreg stty python3; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done
if [ -e "$VOL" ]; then
  die "$VOL is already mounted: some XIAO is in its bootloader, so the copy target is ambiguous. Finish or eject that one first."
fi
if running="$(pgrep -fl 'flash-(watch|reset|impl)\.sh')"; then
  die "flash-watch.sh / flash-reset.sh is running (it copies imprint_dongle.uf2 onto any XIAO-SENSE mount):
$running"
fi

devices="$(usb_devices product "$PRODUCT")" || die "ioreg query failed"
count=$(printf '%s' "$devices" | grep -c .)
if [ "$count" -eq 0 ]; then
  die "no USB device named \"$PRODUCT\". The USB power-only image that preceded the 1200 baud handler does not enumerate, nor does anything behind a charge-only cable: double-tap reset and cp -X by hand (README)."
fi
[ "$count" -eq 1 ] || die "$count USB devices named \"$PRODUCT\"; leave exactly one plugged in:
$(printf '%s\n' "$devices" | tr '\037' ' ')"
IFS=$'\x1f' read -r _ SERIAL SESSION PORTS <<<"$devices"
PORT="${PORTS%% *}"
[ -n "$PORT" ] || die "\"$PRODUCT\" (serial $SERIAL) has no /dev/cu.* port"
say "FOUND $PRODUCT serial=$SERIAL port=$PORT"
[ "$PORT" = "$PORTS" ] || say "      more than one port ($PORTS); the handler listens on all of them"
say "IMAGE $UF2"

# stty opens with O_NONBLOCK; the device may vanish mid-call and fail it, so
# its exit status is logged, not judged. Bounded so a wedged close cannot hang.
t0=$(now_ms)
say "TOUCH stty -f $PORT 1200"
stty -f "$PORT" 1200 &
stty_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
  kill -0 "$stty_pid" 2>/dev/null || break
  sleep 0.2
done
if kill -0 "$stty_pid" 2>/dev/null; then
  kill "$stty_pid" 2>/dev/null
  say "      stty still running after 5s, killed"
fi
wait "$stty_pid"
say "      stty exit=$?"

steps=$((BOOT_TIMEOUT_S * 5))
while [ ! -f "$VOL/INFO_UF2.TXT" ]; do
  steps=$((steps - 1))
  if [ "$steps" -le 0 ]; then
    die "no $VOL within ${BOOT_TIMEOUT_S}s. The firmware lacks the handler or the host sent no 1200 baud line coding: double-tap reset and cp -X by hand (README)."
  fi
  sleep 0.2
done
t_boot=$(now_ms)
say "BOOTLOADER $VOL after $(secs "$t0" "$t_boot")"
# shellcheck disable=SC2001  # indenting every line is clearest with sed
sed 's/^/           /' "$VOL/INFO_UF2.TXT"

steps=$((GONE_TIMEOUT_S * 5))
while :; do
  still="$(usb_devices product "$PRODUCT")" || die "ioreg query failed; nothing copied"
  [ -n "$still" ] || break
  steps=$((steps - 1))
  if [ "$steps" -le 0 ]; then
    die "$VOL mounted but \"$PRODUCT\" is still on USB: another XIAO entered its bootloader. Nothing copied."
  fi
  sleep 0.2
done
boot_dev="$(usb_devices serial "$SERIAL" | cut -d $'\x1f' -f1)"
say "      USB serial $SERIAL now: ${boot_dev:-(no device with this serial)}"

say "COPY $UF2_BASE → $VOL"
cp -X "$UF2" "$VOL/"
cp_rc=$?
sync
say "      cp exit=$cp_rc (an Input/output error here is the bootloader rebooting)"

steps=$((WRITE_TIMEOUT_S * 5))
while [ -f "$VOL/INFO_UF2.TXT" ]; do
  steps=$((steps - 1))
  if [ "$steps" -le 0 ]; then
    die "$VOL still mounted ${WRITE_TIMEOUT_S}s after the copy: the bootloader did not take the image (cp exit=$cp_rc)"
  fi
  sleep 0.2
done
t_written=$(now_ms)
say "WRITTEN $VOL gone after $(secs "$t0" "$t_written")"

deadline=$((t_written + ENUM_TIMEOUT_S * 1000))
back=""
while [ -z "$back" ]; do
  [ "$(now_ms)" -lt "$deadline" ] \
    || die "\"$PRODUCT\" did not enumerate within ${ENUM_TIMEOUT_S}s of the write: the image may lack the handler or not boot. Check the display; recover by double-tap + cp -X."
  sleep 0.5
  back="$(usb_devices product "$PRODUCT")" || die "ioreg query failed"
done
t_back=$(now_ms)
IFS=$'\x1f' read -r _ BACK_SERIAL BACK_SESSION BACK_PORTS <<<"$back"
say "BACK $PRODUCT serial=$BACK_SERIAL port=${BACK_PORTS%% *} after $(secs "$t0" "$t_back")"
[ "$BACK_SERIAL" = "$SERIAL" ] || say "      WARN serial differs from before the touch ($SERIAL)"
[ "$BACK_SESSION" != "$SESSION" ] || say "      WARN same registry session as before the touch"
say "DONE bootloader $(secs "$t0" "$t_boot") / written $(secs "$t0" "$t_written") / back $(secs "$t0" "$t_back"). Check the display."
