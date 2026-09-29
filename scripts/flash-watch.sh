#!/usr/bin/env bash
# Watch /Volumes/ for UF2 bootloader mounts and auto-copy firmware in order:
#   1st assimilator-bt mount → imprint_left.uf2
#   2nd assimilator-bt mount → imprint_right.uf2
#   XIAO BLE mount           → imprint_dongle.uf2
# Exit when all three are flashed.
#
# The body is flash-impl.sh (the NVS reset variant is flash-reset.sh).
# --yes / -y skips the confirmation (one-paste recovery, Claude, CI), as does
# running without a TTY.
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "" "flashed (device will reboot)" "" normal "$@"
