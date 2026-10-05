#!/usr/bin/env bash
# Watch /Volumes/ for UF2 bootloader mounts and auto-copy the images by what
# mounts, one device at a time:
#   a volume whose INFO_UF2.TXT names XIAO → imprint_dongle.uf2
#   the first other volume                 → imprint_left.uf2
#   the next other volume                  → imprint_right.uf2
# Exit when all three are flashed.
#
# The body is flash-impl.sh (the NVS reset variant is flash-reset.sh).
# --yes / -y skips the confirmation (one-paste recovery, Claude, CI), as does
# running without a TTY. Any other argument is ignored (there is no --help or
# --dry-run).
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "" "flashed (device will reboot)" "" normal "$@"
