#!/usr/bin/env bash
# flash-watch.sh / flash-reset.sh の共通実装。
# /Volumes/ を監視し UF2 ブートローダのマウントを検出して順に firmware を copy:
#   1st assimilator-bt mount → imprint_left<SUFFIX>.uf2
#   2nd assimilator-bt mount → imprint_right<SUFFIX>.uf2
#   XIAO BLE mount           → imprint_dongle<SUFFIX>.uf2
# 3 台すべて書き込んだら終了する。
#
# 引数:
#   $1 SUFFIX         firmware ファイル名の suffix（通常 "" / NVS リセット "_RESET"）
#   $2 DONE_NOTE      各デバイス完了行の文言（例 "flashed (device will reboot)"）
#   $3 ALL_DONE_NOTE  最終 ALL DONE 行の末尾に付ける文言（例 " (NVS wiped)"）

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SUFFIX="${1:-}"
DONE_NOTE="${2:-flashed}"
ALL_DONE_NOTE="${3:-}"

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
    # shellcheck disable=SC2001  # 行頭インデント追加は sed が読みやすい
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
      cp "$uf2" "$current/" && sync
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
