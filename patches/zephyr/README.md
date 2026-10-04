# patches/zephyr/

Out-of-tree patches to Zephyr, the `zephyr/` west project (zmkfirmware/zephyr
at `v4.1.0+zmk-fixes`, the revision ZMK's `app/west.yml` imports).
`scripts/zmk-west.sh patch` applies them after
[patches/zmk/](../zmk/README.md), by the rules described there; the local
workspace tree is `~/.cache/zmk-canon/cfgrepo/zephyr`.

## usb-hid-country-code.patch

Adds `CONFIG_USB_HID_COUNTRY_CODE` (int, default 0, range 0–35) to
`subsys/usb/device/class/hid/Kconfig` and writes it into the HID
descriptor's `bCountryCode`, which `core.c` of Zephyr's legacy USB device
stack (the one `ZMK_USB` selects) hard-codes to 0. At the default nothing
changes. canon sets 33 (US) for the Imprint Dongle only
([config/imprint_dongle.conf](../../config/imprint_dongle.conf)).
zmk-hid-host (the ist repository) carries a byte-identical copy under the
same name (compared 2026-10-04).

What 33 does on macOS, and what it does not:

- macOS keeps a keyboard type (ANSI 40, ISO 41, JIS 42) per device in
  `/Library/Preferences/com.apple.keyboardtype.plist`, keyed
  `<productID>-<vendorID>-<countryCode>` in decimal. The Imprint Dongle has
  ZMK's default VID/PID 0x1D50/0x615E, so its key is `24926-7504-33`.
- With 0 it shares `24926-7504-0` with every ZMK device on that VID/PID that
  reports 0, and when that record says ISO, macOS types `§` for HID usage 0x35
  (`` ` ``) and `` ` `` for 0x64. canon hit this on 2026-07-20 (#148, which
  also reverted #147's keymap workaround: the keymap sends GRAVE and TILDE).
- 33 moves the dongle onto `24926-7504-33`, a record it shares only with
  other 0x1D50/0x615E devices that report 33: zmk-hid-host's receivers set 33
  too. That is all: macOS never interprets the value. A device whose key the
  plist lacks starts the Keyboard Setup Assistant whatever its code, and the
  answer is stored under that key, so a Mac that has seen none of these
  devices runs the assistant once (answer ANSI), and one that has seen any of
  them reuses that answer; no code makes the type settle by itself.
- If `` ` `` types `§` again, look at the device and its record, not the
  keymap: `ioreg -r -c IOHIDDevice -l` shows the dongle's `CountryCode`,
  `defaults read /Library/Preferences/com.apple.keyboardtype` the stored type,
  which an answer given for an ist receiver may have written.
- Measured 2026-09-13 on the owner's Mac (zmk-hid-host#72): the dongle reports
  `CountryCode = 33` and matches `24926-7504-33 = 40`. The measurement table
  and the IOHIDFamily and macOS 26.5 references behind these points are in
  [zmk-hid-host's patches/zephyr/README.md](https://github.com/akira-toriyama/zmk-hid-host/blob/main/patches/zephyr/README.md)
  (a private repository; read it with `gh`).

Upstream: not submitted (2026-10-04). Zephyr main still writes 0 in both
stacks: the legacy one, now marked `[DEPRECATED]` in
`subsys/usb/device/Kconfig`, and the new `device_next` HID class
(`HID_DESCRIPTOR_DEFINE` in `subsys/usb/device_next/class/usbd_hid_macros.h`).
Drop this patch when the stack ZMK builds on takes such an option.
