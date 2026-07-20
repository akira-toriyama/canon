# patches/zephyr/

`scripts/build-zmk.sh` / CI (`zmk-build.yml`) がビルド前に `/workspace/zephyr`
（zmkfirmware/zephyr fork, `v4.1.0+zmk-fixes`）へ適用する out-of-tree パッチ群。
適用機構は [patches/zmk/README.md](../zmk/README.md) と同一（毎ビルド冪等再適用・
既適用は reverse-apply check で skip・当たらなければ fail）。

最終ゴールは各パッチを Zephyr 本家（zephyrproject-rtos/zephyr）へ upstream PR し、
取り込まれたらこのディレクトリごと畳むこと。

## パッチ一覧

### `usb-hid-country-code.patch`

`subsys/usb/device/class/hid/` に Kconfig `USB_HID_COUNTRY_CODE`（int, default 0）を
追加し、USB HID descriptor の `bCountryCode`（従来 0 ハードコード）を設定可能にする。

用途: imprint_dongle が `CONFIG_USB_HID_COUNTRY_CODE=33`（US/ANSI）を自己申告する。
bCountryCode=0（未申告）だと macOS はキーボード種別（ANSI/ISO/JIS）を推測や
Keyboard Setup Assistant（per-machine の隠れ状態）で決めるため、ISO 誤判定で
GRAVE(usage 0x35) が keycode 10(§/±) に翻訳される事故が起きる（2026-07-20 実測）。
申告すればどのホストでも接続だけで ANSI が確定し、per-machine 設定が不要になる。
default 0 なので未設定ターゲットの挙動は不変。

**upstream PR**: 未提出（起票済み task 参照）。汎用の Kconfig 追加なので
zephyrproject-rtos/zephyr へそのまま提案可能。merge され次第本 patch を畳む。
