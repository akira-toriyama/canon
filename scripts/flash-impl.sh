#!/usr/bin/env bash
# The body of flash-watch.sh and flash-reset.sh: watch /Volumes for UF2
# bootloader mounts and copy the firmware in order:
#   1st assimilator-bt mount → imprint_left<SUFFIX>.uf2
#   2nd assimilator-bt mount → imprint_right<SUFFIX>.uf2
#   XIAO BLE mount           → imprint_dongle<SUFFIX>.uf2
# Exits once all three are written. Any XIAO mount gets the Imprint Dongle's
# image, the Prospector Dongle's too: flash that one with flash-dongle.sh, and
# never while this runs.
#
# Arguments:
#   $1 SUFFIX         firmware file name suffix ("" normal / "_RESET" NVS reset)
#   $2 DONE_NOTE      text of each device's done line (e.g. "flashed (device will reboot)")
#   $3 ALL_DONE_NOTE  appended to the final ALL DONE line (e.g. " (NVS wiped)")
#   $4 MODE           "normal" / "reset" (wipes NVS, with an extra warning)
#   then [--yes|-y]   skip the confirmation (one-paste recovery, Claude, CI)
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
   • Bootloader = reset "double-tap" (a single tap only reboots; the bonds stay)
   • Left, then right into the bootloader (one board: the mount order decides
     left and right; the dongle, a XIAO, is told apart by itself)
   • If they do not connect, try procedure A first (re-plug the dongle, no
     computer needed) → docs/dongle-roadmap.md
BANNER
if [ "$MODE" = "reset" ]; then
  cat >&2 <<'BANNER'
   ⚠⚠ This wipes NVS (bonds and settings, on every device). Then flash the
      normal images and re-pair with procedure A (the halves advertise
      first, the dongle comes last).
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

LEFT_DONE=0
RIGHT_DONE=0
DONGLE_DONE=0
LAST_MOUNT=""

ts() { date +%H:%M:%S; }

while true; do
  # Find a /Volumes/* that contains INFO_UF2.TXT (= UF2 bootloader)
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
      # assimilator-bt (or non-XIAO) → peripheral
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
      # Wait until volume disappears before scanning again
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
