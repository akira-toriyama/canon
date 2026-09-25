# patches/modules/prospector-zmk-module/

Out-of-tree patches that `scripts/build-zmk.sh` and CI (`zmk-build.yml`) apply
to the west project at `modules/prospector-zmk-module` (t-ogura
`prospector-zmk-module`, tag `v2.2.3`, pinned in
[config/west.yml](../../../config/west.yml)) before every build. The directory
path mirrors the west path, so no mapping table exists. The mechanism is the
one in [patches/zmk/README.md](../../zmk/README.md): re-applied on every build,
an applied patch is detected with a reverse-apply check and skipped, a patch
that does not apply fails the build.

**Re-check every patch here on every module bump** (a new tag in
`config/west.yml`): rebuild, and if a patch no longer applies, regenerate it
against the new tag or drop it when upstream carries the change.

The goal is to send each patch upstream to
[t-ogura/prospector-zmk-module](https://github.com/t-ogura/prospector-zmk-module)
and delete it here once a tag carrying it is pinned. Each patch is a plain
`git diff` against the pinned tag, so it can be submitted unchanged.

## Patches

### `bootloader-on-1200-baud.patch`

Adds `CONFIG_PROSPECTOR_BOOTLOADER_ON_1200_BAUD` (bool, default y, depends on
`PROSPECTOR_MODE_SCANNER && USB_CDC_ACM && RETENTION_BOOT_MODE`, selects
`CDC_ACM_DTE_RATE_CALLBACK_SUPPORT`) and `src/bootloader_on_1200_baud.c`. At
init it registers a CDC ACM line-coding rate callback on every
`zephyr,cdc-acm-uart` instance. When the host sets a port to 1200 baud, it
calls `bootmode_set(BOOT_MODE_TYPE_BOOTLOADER)` and warm-reboots 250 ms later
from a delayable work item.

Why: the Prospector Dongle has no keys for `&bootloader` and its touch panel
is unwired, so the reset double-tap was the only way into the UF2 bootloader.
With this patch `scripts/flash-prospector.sh` can flash it from the Mac alone
(design intent until the first hardware run; see the repository CLAUDE.md).

Design points, from source reads on 2026-09-26 (Zephyr `10ba6d0cb`, ZMK
`9ebbeff0`):

- Not `sys_reboot(0x57)`: the Cortex-M `sys_arch_reboot()` ignores its type
  and calls `NVIC_SystemReset()` (`arch/arm/core/cortex_m/scb.c:38-43`), and
  nothing in the nRF SoC code overrides it; `NRF_STORE_REBOOT_TYPE_GPREGRET`
  was removed in Zephyr 3.6 (`doc/releases/migration-guide-3.6.rst:55-56`).
  The module's touch-UI button in `system_settings_widget.c:73` still calls
  `sys_reboot(0x57)`, so that button is a plain reset on this Zephyr. On ZMK's
  `xiao_ble` board, `bootmode_set()` lands in GPREGRET as 0x57, the Adafruit
  nRF52 bootloader's UF2 magic (ZMK `app/src/boot/bootmode_to_magic_mapper.c:43-52`,
  `app/src/boot/Kconfig.defaults:25`,
  `app/dts/common/nordic/nrf52840_uf2_boot_mode.dtsi`).
- Deferred reboot: the callback runs in the `SET_LINE_CODING` data stage
  (`subsys/usb/device/class/cdc_acm.c:172-187`), and the status stage goes out
  only after the class handler returns (`subsys/usb/device/usb_device.c:384-386`).
  Rebooting inside the callback would leave the host's request unacknowledged.
- The class driver calls back only when the rate changes (`cdc_acm.c:183`), so
  a second 1200 with no other rate in between is ignored; every USB reset
  restores 115200 (`cdc_acm.c:72-73`, `:361-373`, `:387-389`).

**Upstream PR**: not yet submitted.
