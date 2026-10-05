#!/usr/bin/env bash
# The body of flash-watch.sh and flash-reset.sh: watch /Volumes for UF2
# bootloader mounts and copy each image from firmware/ of this checkout by what
# mounts, one device at a time:
#   a volume whose INFO_UF2.TXT names XIAO → imprint_dongle<SUFFIX>.uf2
#   the first other volume                 → imprint_left<SUFFIX>.uf2
#   the next other volume                  → imprint_right<SUFFIX>.uf2
# Exits 0 once all three are written. Each image is looked for only when its
# device mounts: a missing one exits 1 and leaves that device in its
# bootloader. Nothing else may enter a UF2 bootloader while this runs: the
# first XIAO mount gets the Imprint Dongle's image, even the Prospector
# Dongle's (flash that one with flash-dongle.sh), and any other board is taken
# for a half.
#
# Arguments:
#   $1 SUFFIX         image name suffix ("" normal / "_RESET" NVS reset)
#   $2 DONE_NOTE      text of each device's done line (e.g. "flashed (device will reboot)")
#   $3 ALL_DONE_NOTE  appended to the final ALL DONE line (e.g. " (NVS wiped)")
#   $4 MODE           "normal" / "reset" (reset adds the NVS wipe warning to
#                     the banner and the prompt)
#   then [--yes|-y]   skip the confirmation (one-paste recovery, Claude, CI);
#                     any other argument is ignored
#
# The safety banner prints on every run. The confirmation takes Enter alone
# (nothing to type) and is skipped with --yes or without a TTY on stdin
# (Claude, CI), so it never hangs.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SUFFIX="${1:-}"
DONE_NOTE="${2:-flashed}"
ALL_DONE_NOTE="${3:-}"
MODE="${4:-normal}"
if [ "$#" -ge 4 ]; then shift 4; else shift "$#"; fi

YES=0
for _arg in "$@"; do
  case "$_arg" in
    --yes|-y) YES=1 ;;
  esac
done

cat >&2 <<'BANNER'
============================================================
 ⚠ imprint flash: read this first
   • Bootloader = reset "double-tap" (a single tap only reboots: a normal
     image keeps the bonds)
   • Left, then right into the bootloader (one board: the mount order decides
     left and right; the dongle, a XIAO, is told apart by itself)
   • If they do not connect, try procedure A first (re-plug the dongle, no
     computer needed) → docs/recovery.md
BANNER
if [ "$MODE" = "reset" ]; then
  cat >&2 <<'BANNER'
   ⚠⚠ This wipes NVS (bonds and settings, on every device), and the devices
      pair while the RESET images run, so the order matters (docs/recovery.md
      B): the right half off and unplugged; the Imprint Dongle, then the left
      half, then the right half; then flash-watch.sh in the same order. Until
      then a single tap, a replug or a power loss erases a device again.
BANNER
fi
echo "============================================================" >&2

if [ "$YES" -ne 1 ] && [ -t 0 ]; then
  if [ "$MODE" = "reset" ]; then
    printf '%s' " This wipes NVS. Enter to go on / Ctrl-C to stop > " >&2
  else
    printf '%s' " Enter to go on / Ctrl-C to stop > " >&2
  fi
  read -r || exit 130
fi

# The lock flash-dongle.sh takes: while this runs, that script cannot touch a
# dongle into the bootloader, and this cannot start in the middle of its flash
# (it would copy imprint_dongle<SUFFIX>.uf2 onto the volume being written).
LOCK="/tmp/flash-dongle-$(id -u).lock"
exec 9>>"$LOCK" || { echo "cannot open $LOCK" >&2; exit 1; }
lockf -s -t 0 9 || { echo "flash-dongle.sh is flashing a dongle ($LOCK is held): run this afterwards" >&2; exit 1; }

LEFT_DONE=0
RIGHT_DONE=0
DONGLE_DONE=0
LAST_MOUNT=""

ts() { date +%H:%M:%S; }

while true; do
  current=""
  for vol in /Volumes/*/; do
    [[ -f "$vol/INFO_UF2.TXT" ]] || continue
    current="$vol"
    break
  done

  if [[ -n "$current" && "$current" != "$LAST_MOUNT" ]]; then
    info=$(cat "$current/INFO_UF2.TXT" 2>/dev/null)
    name=$(basename "$current")
    echo "[$(ts)] DETECT mount=$name"
    # shellcheck disable=SC2001  # indenting every line is clearest with sed
    echo "$info" | sed 's/^/         /'

    target=""
    if echo "$info" | grep -qi "XIAO"; then
      if [[ $DONGLE_DONE -eq 0 ]]; then target="dongle"; fi
    else
      if   [[ $LEFT_DONE  -eq 0 ]]; then target="left"
      elif [[ $RIGHT_DONE -eq 0 ]]; then target="right"
      fi
    fi

    if [[ -n "$target" ]]; then
      uf2="firmware/imprint_${target}${SUFFIX}.uf2"
      if [[ ! -f "$uf2" ]]; then
        echo "[$(ts)] ERROR uf2 not found: $uf2" >&2
        exit 1
      fi
      echo "[$(ts)] COPY $uf2 → $current"
      cp -X "$uf2" "$current/" && sync
      echo "[$(ts)] DONE  $target $DONE_NOTE"
      case "$target" in
        left)   LEFT_DONE=1   ;;
        right)  RIGHT_DONE=1  ;;
        dongle) DONGLE_DONE=1 ;;
      esac
      LAST_MOUNT="$current"
      # The next device can mount at this same path, so LAST_MOUNT is cleared
      # only once this volume is gone.
      while [[ -f "$current/INFO_UF2.TXT" ]]; do sleep 0.5; done
      echo "[$(ts)] UNMOUNTED $name"
      LAST_MOUNT=""
    else
      echo "[$(ts)] SKIP no remaining target for this device"
      LAST_MOUNT="$current"
    fi
  fi

  if [[ $LEFT_DONE -eq 1 && $RIGHT_DONE -eq 1 && $DONGLE_DONE -eq 1 ]]; then
    echo "[$(ts)] ALL DONE: left + right + dongle${ALL_DONE_NOTE}"
    exit 0
  fi

  sleep 1
done
