#!/usr/bin/env bash
# Flash NVS-reset firmware (*_RESET.uf2) to all 3 devices in order:
#   1st assimilator-bt mount → imprint_left_RESET.uf2
#   2nd assimilator-bt mount → imprint_right_RESET.uf2
#   XIAO BLE mount           → imprint_dongle_RESET.uf2
# After flashing, the device boots, wipes NVS (bond/settings), then
# reboots ready. Pair fresh on next normal firmware flash (or it may
# work directly if the *_RESET.uf2 is a one-shot wipe build).

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

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
      uf2="firmware/imprint_${target}_RESET.uf2"
      if [[ ! -f "$uf2" ]]; then
        echo "[$(ts)] ERROR uf2 not found: $uf2" >&2
        exit 1
      fi
      echo "[$(ts)] COPY $uf2 → $current"
      cp "$uf2" "$current/" && sync
      echo "[$(ts)] DONE  $target NVS reset firmware flashed"
      case "$target" in
        left)   LEFT_DONE=1   ;;
        right)  RIGHT_DONE=1  ;;
        dongle) DONGLE_DONE=1 ;;
      esac
      LAST_MOUNT="$current"
      while [[ -f "$current/INFO_UF2.TXT" ]]; do sleep 0.5; done
      echo "[$(ts)] UNMOUNTED $name"
      LAST_MOUNT=""
    else
      echo "[$(ts)] SKIP no remaining target for this device"
      LAST_MOUNT="$current"
    fi
  fi

  if [[ $LEFT_DONE -eq 1 && $RIGHT_DONE -eq 1 && $DONGLE_DONE -eq 1 ]]; then
    echo "[$(ts)] ALL DONE: left + right + dongle (NVS wiped)"
    exit 0
  fi

  sleep 1
done
