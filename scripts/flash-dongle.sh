#!/usr/bin/env bash
# Flash the Imprint Dongle, the Prospector Dongle or either half of the Cyboard
# Imprint from the Mac alone, without a reset double-tap (named for the dongles
# it began with; the halves joined on 2026-10-19):
#   1. the image names the device: its firmware stamp (the USB manufacturer
#      string, scripts/stamp.py, in the UF2 payload) names the build target,
#      or, for a dongle image built before the stamp, the payload holds that
#      dongle's USB product string; and the file name agrees. Then find the
#      one USB device that is that target (by its stamp, or a dongle by its
#      product string), its USB location, serial and /dev/cu.* port
#      (scripts/dongle.py holds the names and the ioreg lookups)
#   2. set that port to 1200 baud (stty) → the firmware reboots into the UF2
#      bootloader (CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD, zmk-beacon; on the
#      halves since config/cdc_acm_port.dtsi, after #263 of 2026-10-19)
#   3. wait for a UF2 bootloader volume (both dongles mount as XIAO-SENSE,
#      both halves as ASSIMILATOR) whose disk belongs to the USB device at the
#      touched device's USB location: never a volume by name
#   4. cp -X the .uf2 → the volume disappears once the bootloader has taken the
#      image and rebooted
#   5. wait for the device to enumerate again with its /dev/cu.* port, and
#      compare its firmware stamp with the image's: the same stamp before and
#      after the touch cannot tell the copy from the old image
#
#   ./scripts/flash-dongle.sh prospector        # firmware/prospector.uf2
#   ./scripts/flash-dongle.sh imprint_dongle    # firmware/imprint_dongle.uf2
#   ./scripts/flash-dongle.sh imprint_left      # firmware/imprint_left.uf2; imprint_right likewise
#   ./scripts/flash-dongle.sh firmware/prospector-sprite.uf2
#   ./scripts/flash-dongle.sh --dry-run ../zmk-beacon/firmware/prospector.uf2
#
#   --dry-run  run every check up to the 1200 baud touch, print the plan, exit 0
#   --wait N   first poll up to N s for the device with its port (a KVM switch
#              hides both dongles from this Mac)
#   --reset    accept a *_RESET* image: it wipes the device's bonds on every
#              boot, so flash the normal image right after (re-pairing both
#              halves and the Imprint Dongle is flash-reset.sh's job)
#   -h, --help print this header
#
# A bare device name means firmware/<device>.uf2 of this repository; any other
# argument is an image path, from any directory. The payload decides the
# device, and the file name must agree: <device>.uf2, <device>-*.uf2 (a build
# variant such as -logging or -sprite), <device>_RESET.uf2 or
# <device>_RESET-*.uf2 (a tagged reset build). The name keeps out images that
# carry a name but no 1200 baud entry (the probe-*.uf2 spikes carry "Imprint
# Dongle"): they boot, and then strand the next flash. An imprint_dongle*.uf2
# built before 2026-09-27 lacks the entry too, unguarded (its product string
# is in every image); a halves image without config/cdc_acm_port.dtsi (#263 of
# 2026-10-19 and older) is refused, as dongle.py image looks for the port's
# device name, which lands with the entry. A half is reached only over a data
# cable to this Mac while USB powers it (the port is the touch), one half per
# run; both may stay plugged in. A half running the other half's image
# (flash-watch.sh's mount order decides which half gets imprint_left) answers
# here to that image's name; the swap is undone by double-tap, never here.
# Re-enumeration shows that an image booted,
# not which one: the display (Prospector Dongle) or typing (Imprint Dongle, a
# half) is the user's check. The first image with the entry goes on by
# double-tap + cp -X (README; flash-watch.sh for the halves). The checks, the
# hash and the copy all read one snapshot of the image, so a build that
# rewrites it meanwhile cannot slip another image past them.
#
# Refuses to start while another flash-dongle.sh runs (one lock for every
# device, taken before the wait and the mount check), while any UF2 bootloader
# volume is mounted, or while flash-watch.sh / flash-reset.sh run (they copy
# imprint_dongle*.uf2 onto the first XIAO bootloader they see and the halves'
# images onto any other; flash-impl.sh takes the same lock, but only after its
# prompt). Right before the copy it checks for those scripts again, and step
# 3's identity check stands in for the mount check.
#
# A run whose bootloader came up on USB without a UF2 volume that served (no
# volume within the wait, the volume gone before the copy, or still mounted
# long after it) writes the latch, $ZMK_WS/flash-dongle.latch
# (~/.cache/zmk-canon, build-zmk.sh's workspace, so every session and checkout
# shares it), and while it stands every run on the Imprint Dongle or a half is
# refused, --dry-run included. On 2026-10-19 six such runs in a row (two
# sessions, the same hub) each left their device in its bootloader, a keyboard
# that typed nothing until replugged, after the monitor's hub had
# re-enumerated: the bootloader's first mass-storage WRITE timed out
# (0xe00002ed in /usr/bin/log show, sender IOUSBMassStorageDriver) while READ
# and the CDC port worked, and a reboot of the Mac cleared it. The Prospector
# Dongle is never refused: it is the canary, no keyboard. A DONE on any device
# clears the latch; so does a reboot (the latch names the boot it was written
# under), or rm of the file by hand.
#
# Exit status: 0 image copied, bootloader volume released and the device back
# on USB with its port (--dry-run: every check passed) / 1 failed / 2 usage,
# a refused image or a latched run.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 1

VOL=""  # the bootloader volume on the device's USB location, once mounted
STTY_TIMEOUT_S=5
BOOT_TIMEOUT_S=20
COPY_TIMEOUT_S=120
WRITE_TIMEOUT_S=120
ENUM_TIMEOUT_S=30
LATCH="${ZMK_WS:-$HOME/.cache/zmk-canon}/flash-dongle.latch"
USAGE="usage: flash-dongle.sh [--dry-run] [--wait SECONDS] [--reset] <image.uf2 | prospector | imprint_dongle | imprint_left | imprint_right>"
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

# The latch (header). Its lines: boottime= (kern.boottime's seconds, the boot
# it was written under), device=, time=, why=.
boottime() { sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+).*/\1/'; }
latch_set() {
  mkdir -p "$(dirname "$LATCH")" 2>/dev/null
  printf 'boottime=%s\ndevice=%s\ntime=%s\nwhy=%s\n' "$(boottime)" "$DEVICE" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >"$LATCH" 2>/dev/null \
    || say "      WARN cannot write $LATCH"
}
latch_clear() { rm -f "$LATCH" 2>/dev/null || say "      WARN cannot remove $LATCH"; }
# Before anything touches USB: a latch from an earlier boot is stale, the
# Prospector Dongle passes as the canary, a keyboard device is refused.
latch_check() {
  [ -f "$LATCH" ] || return 0
  local boot device time why
  boot="$(sed -n 's/^boottime=//p' "$LATCH")"
  device="$(sed -n 's/^device=//p' "$LATCH")"
  time="$(sed -n 's/^time=//p' "$LATCH")"
  why="$(sed -n 's/^why=//p' "$LATCH")"
  if [ "$boot" != "$(boottime)" ]; then
    say "LATCH from before this boot (${device:-?} at ${time:-?}: ${why:-?}): the reboot cleared it"
    latch_clear
    return 0
  fi
  case "$DEVICE" in
    prospector) say "LATCH ${device:-?} at ${time:-?}: ${why:-?}. The Prospector Dongle is the canary: a DONE here clears it" ;;
    *)
      echo "refusing the $LABEL: the run on the ${device:-?} at ${time:-?} ended with ${why:-?}, and no run has ended in DONE since (latch $LATCH). That failure stranded a keyboard device in its bootloader six times in a row on 2026-10-19, typing nothing until replugged. Flash the Prospector Dongle first; if that fails the same way, reboot the Mac (which cleared it on 2026-10-19) or power-cycle the hub (untested), then try the Prospector Dongle again. rm the latch to flash the $LABEL anyway." >&2
      exit 2 ;;
  esac
}

# The mounted UF2 bootloader volumes (an INFO_UF2.TXT at the root), one per
# line: XIAO-SENSE for either dongle, ASSIMILATOR for either half (seen
# 2026-10-19), a suffixed name for a second one of the same kind.
uf2_volumes() {
  local v
  for v in /Volumes/*/; do
    [ -f "${v}INFO_UF2.TXT" ] && printf '%s\n' "${v%/}"
  done
  return 0
}

# No volume on the device's USB location after the touch: what is on USB there
# tells a touch the firmware ignored from a bootloader macOS did not mount.
# Seen on hardware 2026-09-29: the bootloader enumerated, macOS's write to its
# FAT failed and the mass storage driver gave up after 5 resets; the dongles'
# bootloader 0.6.1 then returns to the app if its USB was not up within 3 s,
# and otherwise stays in the bootloader with no way out but a replug or a
# reset (the halves' 0.9.2: not seen). The app is known by product string and
# manufacturer together: the right half's product string is empty.
no_volume() {
  local at product serial session manufacturer others="" why="/usr/bin/log show --last 5m --info --debug --predicate 'sender == \"IOUSBMassStorageDriver\"' (zsh's builtin log prints nothing; a WRITE timeout reads 0xe00002ed)"
  [ -z "$OTHER_VOLUMES" ] || others=" (UF2 volumes on other USB locations meanwhile: $OTHER_VOLUMES)"
  at="$(dongle at "$LOCATION")" || { latch_set "no volume, and the ioreg query failed"; die_touched "no bootloader volume on USB location $LOCATION within ${BOOT_TIMEOUT_S}s$others, and the ioreg query failed. $LATCHED"; }
  IFS=$'\x1f' read -r product serial session manufacturer <<<"$at"
  if [ "$product" = "$PRODUCT" ] && [ "$manufacturer" = "$MANUFACTURER" ] && [ "$session" = "$SESSION" ]; then
    die "no bootloader volume on USB location $LOCATION within ${BOOT_TIMEOUT_S}s$others, and the $LABEL is still the same USB device: the firmware ignored the touch (no handler, or no 1200 baud line coding reached it). Nothing touched."
  elif [ "$product" = "$PRODUCT" ] && [ "$manufacturer" = "$MANUFACTURER" ]; then
    latch_set "no volume; the device went back to its app"
    die "no bootloader volume on USB location $LOCATION within ${BOOT_TIMEOUT_S}s$others, and the $LABEL rebooted into its app: its bootloader went back to the app because macOS had not set up its USB within 3 s (why: $why), or the reboot missed the bootloader. Nothing copied. $LATCHED"
  elif [ -n "$at" ]; then
    latch_set "no volume; the bootloader stayed on USB"
    die "no bootloader volume within ${BOOT_TIMEOUT_S}s$others, but the bootloader (\"${product:-no product string}\", serial ${serial:--}) is on USB at $LOCATION: no mounted UF2 volume's disk sits under it (why: $why), and it stays in the bootloader once its USB is up, typing nothing. Replug the $LABEL to get its app back; a double-tap + cp -X by hand goes through the same path. $LATCHED"
  fi
  latch_set "no volume; nothing on USB"
  die_touched "no bootloader volume within ${BOOT_TIMEOUT_S}s$others, and nothing is on USB at $LOCATION. $LATCHED"
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
  prospector|imprint_dongle|imprint_left|imprint_right)
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
for tool in ioreg stty df pgrep python3 lockf sysctl; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

# One run at a time, whichever device: both dongles' bootloaders mount as
# XIAO-SENSE and both halves' as ASSIMILATOR, and the mount check below cannot
# see a sibling run's touch until its volume mounts about 2.5 s later. A fixed path, not $TMPDIR, so that every session
# shares it; the kernel drops the lock when the last holder of fd 9 closes it.
LOCK="/tmp/flash-dongle-$(id -u).lock"
exec 9>>"$LOCK" || die "cannot open $LOCK"
lockf -s -t 0 9 || die "another flash-dongle.sh or flash-watch.sh / flash-reset.sh run holds $LOCK: flash one device at a time"

TMP="$(mktemp -d -t flash-dongle)" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT
ERR="$TMP/stderr"
SNAPSHOT="$TMP/$UF2_BASE"
cp "$UF2" "$SNAPSHOT" || die "cannot read $UF2"

image="$(dongle image "$SNAPSHOT" 2>"$ERR")" \
  || refuse "$(sed 's/^dongle\.py: //' "$ERR")"
IFS=$'\x1f' read -r DEVICE PRODUCT SHA256 IMAGE_STAMP <<<"$image"
case "$UF2_BASE" in
  "$DEVICE".uf2|"$DEVICE"-*.uf2|"$DEVICE"_RESET.uf2|"$DEVICE"_RESET-*.uf2) ;;
  *) refuse "its payload is the $DEVICE's, so its name must be $DEVICE.uf2, $DEVICE-*.uf2, ${DEVICE}_RESET.uf2 or ${DEVICE}_RESET-*.uf2 (probe and spike images carry the product string without the 1200 baud entry and would strand the next flash)" ;;
esac
case "$UF2_BASE" in
  *_RESET*) [ "$RESET" -eq 1 ] || refuse "a *_RESET* image wipes the bonds on every boot; pass --reset to flash it anyway (re-pairing both halves and the Imprint Dongle is flash-reset.sh's job)" ;;
  *) [ "$RESET" -eq 0 ] || refuse "--reset is for *_RESET* images only" ;;
esac
case "$DEVICE" in
  prospector)
    LABEL="Prospector Dongle"
    STRANDED="The Prospector Dongle may be left in its bootloader: finish it by hand (double-tap + cp -X, README) or unplug it before flash-watch.sh or flash-reset.sh runs."
    CHECK="Check the display." ;;
  imprint_dongle)
    LABEL="Imprint Dongle"
    STRANDED="The Imprint Dongle may be left in its bootloader, and nothing types until it is finished: finish it by hand (double-tap + cp -X, README)."
    CHECK="Check that both halves type." ;;
  imprint_left|imprint_right)
    LABEL="${DEVICE#imprint_} half"
    STRANDED="The $LABEL may be left in its bootloader: finish it by hand (double-tap + cp -X, README) or unplug it before flash-watch.sh or flash-reset.sh runs (they take any bootloader that is no XIAO for a half, the first for the left)."
    CHECK="Check that the $LABEL types, and lights while USB powers it." ;;
  *) die "no flash messages for device $DEVICE" ;;
esac
LATCHED="The latch $LATCH now refuses the Imprint Dongle and the halves until a run ends in DONE: flash the Prospector Dongle first (no keyboard); if that fails the same way, reboot the Mac (which cleared it on 2026-10-19) or power-cycle the hub (untested), then try the Prospector Dongle again."
latch_check

if [ "$WAIT_S" -gt 0 ]; then
  say "WAIT up to ${WAIT_S}s for the $LABEL with a /dev/cu.* port"
  t_wait=$(now_ms)
  deadline=$((t_wait + WAIT_S * 1000))
  until dongle find "$DEVICE" | cut -d $'\x1f' -f 4 | grep -q .; do
    [ "$(now_ms)" -lt "$deadline" ] || break
    sleep 0.5
  done
  say "      waited $(secs "$t_wait" "$(now_ms)")"
fi

mounted="$(uf2_volumes)"
if [ -n "$mounted" ]; then
  die "a UF2 bootloader volume is already mounted ($(printf '%s' "$mounted" | tr '\n' ' ')): a device is in its bootloader (a double-tap, or an earlier failed run), so the copy target is ambiguous. Finish or eject it first."
fi
if running="$(flashers_running)"; then
  die "flash-watch.sh / flash-reset.sh is running (it copies imprint_dongle*.uf2 onto any XIAO-SENSE mount and the halves' images onto any other UF2 mount):
$running"
fi

devices="$(dongle find "$DEVICE")" || die "ioreg query failed"
count=$(printf '%s' "$devices" | grep -c .)
if [ "$count" -eq 0 ]; then
  die "no $LABEL on USB. A KVM switch hides both dongles from this Mac (--wait N), nothing shows behind a charge-only cable, a half shows only over a data cable while USB powers it and is found by its stamp alone (an image built before the stamp takes flash-watch.sh), and the Prospector Dongle's USB power-only image does not enumerate: double-tap reset and cp -X by hand (README)."
fi
[ "$count" -eq 1 ] || die "$count USB devices are the $LABEL; leave exactly one plugged in:
$(printf '%s\n' "$devices" | tr '\037' ' ')"
IFS=$'\x1f' read -r SERIAL SESSION LOCATION PORTS MANUFACTURER <<<"$devices"
PORT="${PORTS%% *}"
[ -n "$PORT" ] || die "the $LABEL (serial $SERIAL) has no /dev/cu.* port: an image without the 1200 baud entry (flash-watch.sh), or a port still attaching"
say "FOUND $LABEL serial=$SERIAL location=$LOCATION port=$PORT"
[ "$PORT" = "$PORTS" ] || say "      more than one port ($PORTS); the handler listens on all of them"
say "IMAGE $UF2 sha256=${SHA256:0:12}"
say "STAMP image: ${IMAGE_STAMP:-none (built before the stamp)}; on the device now: \"$MANUFACTURER\""

if [ "$DRY_RUN" -eq 1 ]; then
  say "PLAN stty -f $PORT 1200, wait up to ${BOOT_TIMEOUT_S}s for a UF2 bootloader volume on USB location $LOCATION, cp -X $UF2_BASE, wait for the $LABEL to come back with its port and read its stamp"
  say "DRY RUN $DEVICE serial=$SERIAL $UF2 sha256=${SHA256:0:12}: nothing touched"
  exit 0
fi

# stty opens with O_NONBLOCK; the device may vanish mid-call and fail it, so
# its exit status is logged, not judged.
t0=$(now_ms)
say "TOUCH stty -f $PORT 1200"
run_bounded "$STTY_TIMEOUT_S" "$ERR" stty -f "$PORT" 1200
say "      stty exit=$BOUNDED_RC$([ "$BOUNDED_RC" -ne 124 ] || echo " (killed after ${STTY_TIMEOUT_S}s)") $(tr '\n' ' ' <"$ERR")"

# Identity, not presence: the device having left USB does not make a mounted
# volume its own (the other dongle may hold XIAO-SENSE, the other half
# ASSIMILATOR, while this one's mounts under a suffixed name). Its
# bootloader enumerates on the same USB port, so the volume taken is the one
# whose disk sits under the device at LOCATION; every other is left alone. A
# volume still mounting fails the owner lookup and is tried again.
deadline=$((t0 + BOOT_TIMEOUT_S * 1000))
OTHER_VOLUMES=""
while [ -z "$VOL" ]; do
  OTHER_VOLUMES=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    owner="$(dongle owner "$candidate" 2>/dev/null)" || continue
    IFS=$'\x1f' read -r disk OWNER_PRODUCT OWNER_SERIAL _ OWNER_LOCATION <<<"$owner"
    if [ -n "$OWNER_LOCATION" ] && [ "$OWNER_LOCATION" = "$LOCATION" ]; then
      VOL="$candidate"
      break
    fi
    OTHER_VOLUMES="$OTHER_VOLUMES$candidate@${OWNER_LOCATION:-?} "
  done <<<"$(uf2_volumes)"
  [ -z "$VOL" ] || break
  [ "$(now_ms)" -lt "$deadline" ] || no_volume
  sleep 0.2
done
t_boot=$(now_ms)
say "BOOTLOADER $VOL after $(secs "$t0" "$t_boot")"
# shellcheck disable=SC2001  # indenting every line is clearest with sed
sed 's/^/           /' "$VOL/INFO_UF2.TXT"
say "      $VOL is $disk on USB location $OWNER_LOCATION: ${OWNER_PRODUCT:-(no product string)} serial=${OWNER_SERIAL:-(none)}"

if running="$(flashers_running)"; then
  die_touched "flash-watch.sh / flash-reset.sh started meanwhile. Nothing copied. Stop it first:
$running
"
fi
[ -f "$VOL/INFO_UF2.TXT" ] || { latch_set "the volume went away before the copy"; die_touched "$VOL went away before the copy. Nothing copied. $LATCHED"; }

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
    || { latch_set "the volume stayed mounted ${WRITE_TIMEOUT_S}s after the copy"; die_touched "$VOL still mounted ${WRITE_TIMEOUT_S}s after the copy: the bootloader did not take the image. $LATCHED"; }
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
    IFS=$'\x1f' read -r BACK_SERIAL BACK_SESSION BACK_LOCATION BACK_PORTS BACK_MANUFACTURER <<<"$back"
    [ -z "$BACK_PORTS" ] || break
  fi
  if [ "$(now_ms)" -ge "$deadline" ]; then
    [ -n "$back" ] \
      && die "the $LABEL enumerated but has no /dev/cu.* port ${ENUM_TIMEOUT_S}s after the write. $CHECK"
    die_touched "the $LABEL did not enumerate within ${ENUM_TIMEOUT_S}s of the write: the image may not boot. $CHECK"
  fi
  sleep 0.5
done
t_back=$(now_ms)
say "BACK $LABEL serial=$BACK_SERIAL location=$BACK_LOCATION port=$BACK_PORTS after $(secs "$t0" "$t_back")"
[ "$BACK_SERIAL" = "$SERIAL" ] || say "      WARN serial differs from before the touch ($SERIAL)"
[ "$BACK_LOCATION" = "$LOCATION" ] || say "      WARN location differs from before the touch ($LOCATION)"
[ "$BACK_SESSION" != "$SESSION" ] || say "      WARN same registry session as before the touch"
if [ -z "$IMAGE_STAMP" ]; then
  say "STAMP the image has none; the device reports \"$BACK_MANUFACTURER\""
elif [ "$BACK_MANUFACTURER" != "$IMAGE_STAMP" ]; then
  say "      WARN the device reports \"$BACK_MANUFACTURER\", not the image's stamp \"$IMAGE_STAMP\": another image booted"
elif [ "$MANUFACTURER" = "$IMAGE_STAMP" ]; then
  say "STAMP $BACK_MANUFACTURER (the same as before the touch: the stamp cannot tell this copy from the old image)"
else
  say "STAMP $BACK_MANUFACTURER (the image's; before the touch: \"$MANUFACTURER\")"
fi
say "TIMES bootloader $(secs "$t0" "$t_boot") / written $(secs "$t0" "$t_written") / back $(secs "$t0" "$t_back"). $CHECK"
latch_clear
say "DONE $DEVICE serial=$BACK_SERIAL $UF2 sha256=${SHA256:0:12}"
