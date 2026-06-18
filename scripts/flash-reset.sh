#!/usr/bin/env bash
# Flash NVS-reset firmware (*_RESET.uf2) to all 3 devices in order:
#   1st assimilator-bt mount → imprint_left_RESET.uf2
#   2nd assimilator-bt mount → imprint_right_RESET.uf2
#   XIAO BLE mount           → imprint_dongle_RESET.uf2
# After flashing, the device boots, wipes NVS (bond/settings), then
# reboots ready. Pair fresh on next normal firmware flash (or it may
# work directly if the *_RESET.uf2 is a one-shot wipe build).
#
# 共通実装は flash-impl.sh（通常版は flash-watch.sh）。
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "_RESET" "NVS reset firmware flashed" " (NVS wiped)"
