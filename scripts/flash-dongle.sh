#!/usr/bin/env bash
# Flash the Imprint Dongle or the Prospector Dongle from the Mac alone, without
# a reset double-tap:
#   1. the image names the device: its UF2 payload holds exactly one of the
#      dongles' USB product strings, and its file name agrees; then find the
#      one USB device with that product string, its USB location, serial and
#      /dev/cu.* port (scripts/dongle.py holds the product strings and the
#      ioreg lookups)
#   2. set that port to 1200 baud (stty) → the firmware reboots into the UF2
#      bootloader (CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD, zmk-beacon)
#   3. wait for /Volumes/XIAO-SENSE and check that its disk belongs to the USB
#      device at the dongle's USB location
#   4. cp -X the .uf2 → the volume disappears once the bootloader has taken the
#      image and rebooted
#   5. wait for the product string to enumerate again with its /dev/cu.* port
#
#   ./scripts/flash-dongle.sh prospector        # firmware/prospector.uf2
#   ./scripts/flash-dongle.sh imprint_dongle    # firmware/imprint_dongle.uf2
#   ./scripts/flash-dongle.sh firmware/prospector-sprite.uf2
#   ./scripts/flash-dongle.sh --dry-run ../zmk-beacon/firmware/prospector.uf2
#
#   --dry-run  run every check up to the 1200 baud touch, print the plan, exit 0
#   --wait N   first poll up to N s for the dongle with its port (a KVM switch
#              hides both dongles from this Mac)
#   --reset    accept a *_RESET* image: it wipes the dongle's bonds on every
#              boot, so flash the normal image right after (re-pairing both
#              halves and the Imprint Dongle is flash-reset.sh's job)
#   -h, --help print this header
#
# A bare device name means firmware/<device>.uf2 of this repository; any other
# argument is an image path, from any directory. The payload decides the
# device, and the file name must agree: <device>.uf2, <device>-*.uf2 (a build
# variant such as -logging or -sprite), <device>_RESET.uf2 or
# <device>_RESET-*.uf2 (a tagged reset build). The name keeps
# out images that carry a product string but no 1200 baud entry (the
# probe-*.uf2 spikes carry "Imprint Dongle"): they boot, and then strand the
# next flash. An imprint_dongle*.uf2 built before 2026-09-27 lacks the entry
# too. Re-enumeration shows that an image booted, not which one: the display
# (Prospector Dongle) or typing (Imprint Dongle) is the user's check. The first
# image with the entry goes on by double-tap + cp -X (README). The checks, the
# hash and the copy all read one snapshot of the image, so a build that
# rewrites it meanwhile cannot slip another image past them.
#
# Refuses to start while another flash-dongle.sh runs (one lock for either
# dongle, taken before the wait and the mount check), while /Volumes/XIAO-SENSE
# is mounted, or while flash-watch.sh / flash-reset.sh run (both dongles mount
# as XIAO-SENSE, and those scripts copy imprint_dongle*.uf2 onto the first XIAO
# bootloader they see; flash-impl.sh takes the same lock, but only after its
# prompt). Right before the copy it checks for those scripts again, and step
# 3's identity check stands in for the mount check.
#
# Exit status: 0 image copied, bootloader volume released and the dongle back
# on USB with its port (--dry-run: every check passed) / 1 failed / 2 usage or
# a refused image.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 1

VOL="/Volumes/XIAO-SENSE"
STTY_TIMEOUT_S=5
BOOT_TIMEOUT_S=20
COPY_TIMEOUT_S=120
WRITE_TIMEOUT_S=120
ENUM_TIMEOUT_S=30
USAGE="usage: flash-dongle.sh [--dry-run] [--wait SECONDS] [--reset] <image.uf2 | prospector | imprint_dongle>"
STRANDED=""

ts() { date +%H:%M:%S; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR $*" >&2; exit 1; }
die_touched() { die "$* $STRANDED"; }
refuse() { echo "refusing $UF2_ARG: $*" >&2; exit 2; }
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1fs", (b - a) / 1000 }'; }
dongle() { python3 "$REPO/scripts/dongle.py" "$@"; }

# Runs "$@" for at most $1 s with its stderr in file $2. BOUNDED_RC gets the
# exit status, or 124 once it had to be killed. A process that survives SIGKILL
# (a close on a vanished USB volume can sleep uninterruptibly) is left behind,
# never waited on.
run_bounded() {
  local limit_ms=$(($1 * 1000)) err="$2" pid start
  shift 2
  # 9>&-: a child left in uninterruptible sleep must not keep the run lock.
  "$@" 2>"$err" 9>&- &
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

flashers_running() { pgrep -fl 'flash-(watch|reset|impl)\.sh'; }

# No volume after the touch: what is on USB at the dongle's location tells a
# touch the firmware ignored from a bootloader macOS did not mount. Seen on
# hardware 2026-09-29: the bootloader enumerated, macOS's write to its FAT
# failed and the mass storage driver gave up after 5 resets; bootloader 0.6.1
# then returns to the app if its USB was not up within 3 s, and otherwise
# stays in the bootloader with no way out but a replug or a reset.
no_volume() {
  local at product serial session why="log show --last 5m --predicate 'sender == \"IOUSBMassStorageDriver\"'"
  at="$(dongle at "$LOCATION")" || die_touched "no $VOL within ${BOOT_TIMEOUT_S}s, and the ioreg query failed."
  IFS=$'\x1f' read -r product serial session <<<"$at"
  if [ "$product" = "$PRODUCT" ] && [ "$session" = "$SESSION" ]; then
    die "no $VOL within ${BOOT_TIMEOUT_S}s, and \"$PRODUCT\" is still the same USB device: the firmware ignored the touch (no handler, or no 1200 baud line coding reached it). Nothing touched."
  elif [ "$product" = "$PRODUCT" ]; then
    die "no $VOL within ${BOOT_TIMEOUT_S}s, and \"$PRODUCT\" rebooted into its app: its bootloader went back to the app because macOS had not set up its USB within 3 s (why: $why), or the reboot missed the bootloader. Nothing copied."
  elif [ -n "$at" ]; then
    die_touched "no $VOL within ${BOOT_TIMEOUT_S}s, but the bootloader (\"${product:-no product string}\", serial ${serial:--}) is on USB at $LOCATION: macOS mounted no volume (why: $why), and it stays in the bootloader once its USB is up. Replug the dongle, then flash again."
  fi
  die_touched "no $VOL within ${BOOT_TIMEOUT_S}s, and nothing is on USB at $LOCATION."
}

DRY_RUN=0
RESET=0
WAIT_S=0
UF2_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --reset) RESET=1 ;;
    --wait)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "--wait takes a whole number of seconds" >&2; exit 2; }
      WAIT_S=$((10#$2))
      shift ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)
      [ -z "$UF2_ARG" ] || { echo "exactly one image or device" >&2; exit 2; }
      UF2_ARG="$1" ;;
  esac
  shift
done
[ -n "$UF2_ARG" ] || { echo "$USAGE" >&2; exit 2; }

BUILD_HINT=""
case "$UF2_ARG" in
  prospector|imprint_dongle)
    UF2_PATH="$REPO/firmware/$UF2_ARG.uf2"
    BUILD_HINT=" (build it: ./scripts/build-zmk.sh $UF2_ARG)" ;;
  *) UF2_PATH="$UF2_ARG" ;;
esac
UF2_BASE="$(basename "$UF2_PATH")"
UF2_DIR="$(cd "$(dirname "$UF2_PATH")" 2>/dev/null && pwd -P)" || UF2_DIR=""
UF2="$UF2_DIR/$UF2_BASE"
# A link's name need not describe the image it points to.
[ ! -L "$UF2" ] || refuse "a symlink"
{ [ -n "$UF2_DIR" ] && [ -f "$UF2" ]; } || die "$UF2_PATH not found$BUILD_HINT"

[ "$(uname -s)" = Darwin ] || die "macOS only (ioreg, stty -f, /Volumes)"
for tool in ioreg stty df pgrep python3 lockf; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

# One run at a time, whichever dongle: both bootloaders mount as XIAO-SENSE,
# and the mount check below cannot see a sibling run's touch until its volume
# mounts about 2.5 s later. A fixed path, not $TMPDIR, so that every session
# shares it; the kernel drops the lock when the last holder of fd 9 closes it.
LOCK="/tmp/flash-dongle-$(id -u).lock"
exec 9>>"$LOCK" || die "cannot open $LOCK"
lockf -s -t 0 9 || die "another flash-dongle.sh or flash-watch.sh / flash-reset.sh run holds $LOCK: flash one dongle at a time"

TMP="$(mktemp -d -t flash-dongle)" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT
ERR="$TMP/stderr"
SNAPSHOT="$TMP/$UF2_BASE"
cp "$UF2" "$SNAPSHOT" || die "cannot read $UF2"

image="$(dongle image "$SNAPSHOT" 2>"$ERR")" \
  || refuse "$(sed 's/^dongle\.py: //' "$ERR")"
IFS=$'\x1f' read -r DEVICE PRODUCT SHA256 <<<"$image"
case "$UF2_BASE" in
  "$DEVICE".uf2|"$DEVICE"-*.uf2|"$DEVICE"_RESET.uf2|"$DEVICE"_RESET-*.uf2) ;;
  *) refuse "its payload is the $PRODUCT's, so its name must be $DEVICE.uf2, $DEVICE-*.uf2, ${DEVICE}_RESET.uf2 or ${DEVICE}_RESET-*.uf2 (probe and spike images carry the product string without the 1200 baud entry and would strand the next flash)" ;;
esac
case "$UF2_BASE" in
  *_RESET*) [ "$RESET" -eq 1 ] || refuse "a *_RESET* image wipes the bonds on every boot; pass --reset to flash it anyway (re-pairing both halves and the Imprint Dongle is flash-reset.sh's job)" ;;
  *) [ "$RESET" -eq 0 ] || refuse "--reset is for *_RESET* images only" ;;
esac
case "$DEVICE" in
  prospector)
    STRANDED="The Prospector Dongle may be left in its bootloader: finish it by hand (double-tap + cp -X, README) or unplug it before flash-watch.sh or flash-reset.sh runs."
    CHECK="Check the display." ;;
  imprint_dongle)
    STRANDED="The Imprint Dongle may be left in its bootloader, and nothing types until it is finished: finish it by hand (double-tap + cp -X, README)."
    CHECK="Check that both halves type." ;;
  *) die "no flash messages for device $DEVICE" ;;
esac

if [ "$WAIT_S" -gt 0 ]; then
  say "WAIT up to ${WAIT_S}s for \"$PRODUCT\" with a /dev/cu.* port"
  t_wait=$(now_ms)
  deadline=$((t_wait + WAIT_S * 1000))
  until dongle find "$DEVICE" | cut -d $'\x1f' -f 4 | grep -q .; do
    [ "$(now_ms)" -lt "$deadline" ] || break
    sleep 0.5
  done
  say "      waited $(secs "$t_wait" "$(now_ms)")"
fi

if [ -e "$VOL" ]; then
  die "$VOL is already mounted: a dongle is in its bootloader (a double-tap, or an earlier failed run), so the copy target is ambiguous. Finish or eject that one first."
fi
if running="$(flashers_running)"; then
  die "flash-watch.sh / flash-reset.sh is running (it copies imprint_dongle.uf2 onto any XIAO-SENSE mount):
$running"
fi

devices="$(dongle find "$DEVICE")" || die "ioreg query failed"
count=$(printf '%s' "$devices" | grep -c .)
if [ "$count" -eq 0 ]; then
  die "no USB device named \"$PRODUCT\". A KVM switch hides both dongles from this Mac (--wait N), nothing shows behind a charge-only cable, and the Prospector Dongle's USB power-only image does not enumerate: double-tap reset and cp -X by hand (README)."
fi
[ "$count" -eq 1 ] || die "$count USB devices named \"$PRODUCT\"; leave exactly one plugged in:
$(printf '%s\n' "$devices" | tr '\037' ' ')"
IFS=$'\x1f' read -r SERIAL SESSION LOCATION PORTS <<<"$devices"
PORT="${PORTS%% *}"
[ -n "$PORT" ] || die "\"$PRODUCT\" (serial $SERIAL) has no /dev/cu.* port"
say "FOUND $PRODUCT serial=$SERIAL location=$LOCATION port=$PORT"
[ "$PORT" = "$PORTS" ] || say "      more than one port ($PORTS); the handler listens on all of them"
say "IMAGE $UF2 sha256=${SHA256:0:12}"

if [ "$DRY_RUN" -eq 1 ]; then
  say "PLAN stty -f $PORT 1200, wait up to ${BOOT_TIMEOUT_S}s for $VOL on USB location $LOCATION, cp -X $UF2_BASE, wait for \"$PRODUCT\" to come back with its port"
  say "DRY RUN $DEVICE serial=$SERIAL $UF2 sha256=${SHA256:0:12}: nothing touched"
  exit 0
fi

# stty opens with O_NONBLOCK; the device may vanish mid-call and fail it, so
# its exit status is logged, not judged.
t0=$(now_ms)
say "TOUCH stty -f $PORT 1200"
run_bounded "$STTY_TIMEOUT_S" "$ERR" stty -f "$PORT" 1200
say "      stty exit=$BOUNDED_RC$([ "$BOUNDED_RC" -ne 124 ] || echo " (killed after ${STTY_TIMEOUT_S}s)") $(tr '\n' ' ' <"$ERR")"

deadline=$((t0 + BOOT_TIMEOUT_S * 1000))
until [ -f "$VOL/INFO_UF2.TXT" ]; do
  [ "$(now_ms)" -lt "$deadline" ] || no_volume
  sleep 0.2
done
t_boot=$(now_ms)
say "BOOTLOADER $VOL after $(secs "$t0" "$t_boot")"
# shellcheck disable=SC2001  # indenting every line is clearest with sed
sed 's/^/           /' "$VOL/INFO_UF2.TXT"

# Identity, not presence: the dongle having left USB does not make $VOL its
# volume (the other dongle may hold XIAO-SENSE while this one's mounts under a
# suffixed name). Its bootloader enumerates on the same USB port, so the disk
# behind $VOL must sit under the device at LOCATION.
owner="$(dongle owner "$VOL" 2>"$ERR")" || die_touched "$(sed 's/^dongle\.py: //' "$ERR"). Nothing copied."
IFS=$'\x1f' read -r disk OWNER_PRODUCT OWNER_SERIAL _ OWNER_LOCATION <<<"$owner"
say "      $VOL is $disk on USB location ${OWNER_LOCATION:-(none)}: ${OWNER_PRODUCT:-(no product string)} serial=${OWNER_SERIAL:-(none)}"
if [ -z "$OWNER_LOCATION" ] || [ "$OWNER_LOCATION" != "$LOCATION" ]; then
  die_touched "$VOL is not on the $PRODUCT's USB location ($LOCATION): another board's bootloader holds it. Nothing copied."
fi

if running="$(flashers_running)"; then
  die_touched "flash-watch.sh / flash-reset.sh started meanwhile. Nothing copied. Stop it first:
$running
"
fi
[ -f "$VOL/INFO_UF2.TXT" ] || die_touched "$VOL went away before the copy. Nothing copied."

say "COPY $UF2_BASE → $VOL"
run_bounded "$COPY_TIMEOUT_S" "$ERR" cp -X "$SNAPSHOT" "$VOL/"
cp_rc=$BOUNDED_RC
cp_err="$(tr '\n' ' ' <"$ERR")"
case "$cp_rc" in
  0) say "      cp exit=0" ;;
  124) die_touched "cp -X still running after ${COPY_TIMEOUT_S}s, killed." ;;
  *)
    case "$cp_err" in
      *"Input/output error"*|*"Device not configured"*)
        say "      cp exit=$cp_rc: $cp_err(the bootloader rebooting under the copy)" ;;
      # Other errno texts of a volume vanishing under cp are not ruled out, and
      # a failed copy leaves the volume mounted, so the wait below decides.
      *) say "      cp exit=$cp_rc: $cp_err(unrecognised; the volume and re-enumeration decide)" ;;
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

# Back means its /dev/cu.* port is attached too: the serial driver attaches
# after the device appears, and the next run needs the port.
deadline=$((t_written + ENUM_TIMEOUT_S * 1000))
BACK_PORTS=""
while :; do
  back="$(dongle find "$DEVICE")" || die "ioreg query failed"
  if [ -n "$back" ]; then
    IFS=$'\x1f' read -r BACK_SERIAL BACK_SESSION BACK_LOCATION BACK_PORTS <<<"$back"
    [ -z "$BACK_PORTS" ] || break
  fi
  if [ "$(now_ms)" -ge "$deadline" ]; then
    [ -n "$back" ] \
      && die "\"$PRODUCT\" enumerated but has no /dev/cu.* port ${ENUM_TIMEOUT_S}s after the write. $CHECK"
    die_touched "\"$PRODUCT\" did not enumerate within ${ENUM_TIMEOUT_S}s of the write: the image may not boot. $CHECK"
  fi
  sleep 0.5
done
t_back=$(now_ms)
say "BACK $PRODUCT serial=$BACK_SERIAL location=$BACK_LOCATION port=$BACK_PORTS after $(secs "$t0" "$t_back")"
[ "$BACK_SERIAL" = "$SERIAL" ] || say "      WARN serial differs from before the touch ($SERIAL)"
[ "$BACK_LOCATION" = "$LOCATION" ] || say "      WARN location differs from before the touch ($LOCATION)"
[ "$BACK_SESSION" != "$SESSION" ] || say "      WARN same registry session as before the touch"
say "TIMES bootloader $(secs "$t0" "$t_boot") / written $(secs "$t0" "$t_written") / back $(secs "$t0" "$t_back"). $CHECK"
say "DONE $DEVICE serial=$BACK_SERIAL $UF2 sha256=${SHA256:0:12}"
