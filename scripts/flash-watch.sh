#!/usr/bin/env bash
# Watch /Volumes/ for UF2 bootloader mounts and auto-copy firmware in order:
#   1st assimilator-bt mount → imprint_left.uf2
#   2nd assimilator-bt mount → imprint_right.uf2
#   XIAO BLE mount           → imprint_dongle.uf2
# Exit when all three are flashed.
#
# 共通実装は flash-impl.sh（NVS リセット版は flash-reset.sh）。
# --yes / -y で確認スキップ（コピペ一発復旧・Claude・CI 用）。非対話でも自動スキップ。
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "" "flashed (device will reboot)" "" normal "$@"
