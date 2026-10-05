#!/usr/bin/env bash
# Flash the NVS-reset images (*_RESET.uf2) to all 3 devices by what mounts,
# one device at a time:
#   a volume whose INFO_UF2.TXT names XIAO → imprint_dongle_RESET.uf2
#   the first other volume                 → imprint_left_RESET.uf2
#   the next other volume                  → imprint_right_RESET.uf2
# For bonds that re-plugging the Imprint Dongle (docs/recovery.md A) cannot
# fix. The *_RESET.uf2 is the normal build plus ZMK's
# CONFIG_ZMK_SETTINGS_RESET_ON_START=y, so it wipes NVS (bond/settings) on
# EVERY boot and then runs Bluetooth: the devices pair while it runs, and the
# normal image flashed next (./scripts/flash-watch.sh, which removes the
# wipe-on-boot) keeps those bonds. Hence the order of docs/recovery.md B: the
# Imprint Dongle first, then left, then right (right half off and unplugged
# until its turn).
#
# Build the images first: `./scripts/build-zmk.sh imprint --reset` writes
# firmware/imprint_{left,right,dongle}_RESET.uf2.
# The body is flash-impl.sh (the normal variant is flash-watch.sh).
# --yes / -y skips the confirmation (one-paste recovery, Claude, CI), as does
# running without a TTY. Any other argument is ignored (there is no --help or
# --dry-run).
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "_RESET" "NVS reset image flashed" " (NVS wiped)" reset "$@"
