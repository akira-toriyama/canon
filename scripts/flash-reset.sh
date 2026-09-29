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
# Build the images first: `./scripts/build-zmk.sh imprint --reset` writes
# firmware/imprint_{left,right,dongle}_RESET.uf2.
# The body is flash-impl.sh (the normal variant is flash-watch.sh).
# --yes / -y skips the confirmation (one-paste recovery, Claude, CI), as does
# running without a TTY.
exec "$(dirname "${BASH_SOURCE[0]}")/flash-impl.sh" "_RESET" "NVS reset firmware flashed" " (NVS wiped)" reset "$@"
