#!/usr/bin/env bash
# Flash NVS-reset firmware (*_RESET.uf2) to all 3 devices in order:
#   1st assimilator-bt mount → imprint_left_RESET.uf2
#   2nd assimilator-bt mount → imprint_right_RESET.uf2
#   XIAO BLE mount           → imprint_dongle_RESET.uf2
# Use when BLE pairing wedges (split halves won't re-pair, dongle lost the
# keyboard, etc.). The *_RESET.uf2 is the normal firmware built with ZMK's
# CONFIG_ZMK_SETTINGS_RESET_ON_START=y, so it wipes NVS (bond/settings) on
# EVERY boot. Per device:
#   ① flash *_RESET.uf2 (this script) → wipes on boot → ② flash the normal
#   firmware (./scripts/flash-watch.sh, removes the wipe-on-boot) → pair fresh.
#
# 先に成果物を作る: `./scripts/build-zmk.sh imprint --reset`
#   → firmware/imprint_{left,right,dongle}_RESET.uf2 を生成。
# 共通実装は flash-impl.sh（通常版は flash-watch.sh）。
# --yes / -y で確認スキップ（コピペ一発復旧・Claude・CI 用）。非対話でも自動スキップ。
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "_RESET" "NVS reset firmware flashed" " (NVS wiped)" reset "$@"
