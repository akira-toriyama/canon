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
#   $4 MODE           "normal"（通常焼き）/ "reset"（NVS 全消去・追加警告つき）
#   以降 [--yes|-y]   確認をスキップ（コピペ一発復旧 / Claude / CI 用）
#
# 安全 banner は毎回必ず出す。確認プロンプトは「タイプ不要（Enter のみ）」で、
# --yes 指定時 or 非対話（非 TTY = Claude/CI）時は自動スキップしてハングしない。

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SUFFIX="${1:-}"
DONE_NOTE="${2:-flashed}"
ALL_DONE_NOTE="${3:-}"
MODE="${4:-normal}"
[ "$#" -ge 4 ] && shift 4 || shift "$#"

YES=0
for _arg in "$@"; do
  case "$_arg" in
    --yes|-y) YES=1 ;;
  esac
done

# ── 安全 banner（誰が叩いても必ず出る。詳細復旧は docs/dongle-roadmap.md） ──
cat >&2 <<'BANNER'
============================================================
 ⚠ imprint フラッシュ — 必ず確認
   • ブートローダ = リセット "ダブルタップ"（シングルは再起動だけ＝bond は消えない）
   • 左→右の順でブートローダへ（同じ基板＝マウント順で左右決定。dongle=XIAO は自動判別）
   • 繋がらない時の復旧は手順A（ドングル抜き挿し・PC 不要）優先 → docs/dongle-roadmap.md
BANNER
if [ "$MODE" = "reset" ]; then
  cat >&2 <<'BANNER'
   ⚠⚠ これは NVS 全消去（bond/設定が全デバイスで消える）。消去後に通常版を焼き、
      手順A（子機を先に広告 → 最後にドングル）で再ペアリングすること。
BANNER
fi
echo "============================================================" >&2

# 確認（--yes / 非対話 はスキップ＝コピペ一発・Claude・CI で詰まらない。タイプ不要）
if [ "$YES" -ne 1 ] && [ -t 0 ]; then
  if [ "$MODE" = "reset" ]; then
    printf '%s' " NVS 全消去を実行します。Enter で続行 / Ctrl-C で中止 > " >&2
  else
    printf '%s' " Enter で続行 / Ctrl-C で中止 > " >&2
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
