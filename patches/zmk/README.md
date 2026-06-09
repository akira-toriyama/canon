# patches/zmk/

`scripts/build-zmk.sh` がビルド前に `/workspace/zmk` へ適用する
out-of-tree パッチ群。`west update` で巻き戻されるたびに毎ビルド
冪等に再適用される(既適用は reverse-apply check で検出して skip)。

最終ゴールは各パッチを `zmkfirmware/zmk` へ upstream PR し、取り込まれ
たらこのディレクトリごと畳むこと。詳細は
[docs/dongle-roadmap.md](../../docs/dongle-roadmap.md) の
「ZMK source patch (out-of-tree)」節を参照。

## パッチ一覧

### `security-changed-auto-unpair.patch`

`app/src/ble.c` の `security_changed` で
`BT_SECURITY_ERR_PIN_OR_KEY_MISSING` を受けたピアを `bt_unpair` →
`bt_conn_disconnect` する。dongle 構成で central(XIAO BLE) と
peripheral(左右半分) の bond が片側だけ失われたときの自動復帰用。
このパッチが無いと、再接続時に PIN_OR_KEY_MISSING でハンドシェイクが
ループしてユーザー操作では復帰できない。

**upstream PR**: [zmkfirmware/zmk#3385](https://github.com/zmkfirmware/zmk/pull/3385)
(`CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISSING`、default n の Kconfig gate
付き)。merge され次第本 patch を畳む。

### `usb-hid-prime-on-ready.patch`

`app/src/usb_hid.c` に **pending report queue** を追加し、USB が
`USB_DC_SUSPEND` で破棄していた HID report を貯めて、`USB_DC_CONFIGURED`
/ `USB_DC_RESUME` 復帰の 100ms 後に flush する。

カバーする 3 症状 (いずれも「USB ready 直後の HID drop」共通機構):

- dongle 物理つけ外し直後の 1 打目消失
- PC スリープ復帰直後の 1 打目消失
- 長時間無操作 (macOS USB selective suspend) 復帰時、数打必要

ZMK 現実装 [`zmk_usb_hid_send_report`](https://github.com/zmkfirmware/zmk/blob/main/app/src/usb_hid.c#L187)
は `USB_DC_SUSPEND` で `usb_wakeup_request()` だけ返して report を
完全破棄、`USB_DC_DISCONNECTED` / `RESET` / `UNKNOWN` でも `-ENODEV`
で破棄。queue 化することで「破棄されていた打鍵」を resume 後に
取り戻せる。100ms の flush delay は host (macOS) HID interface binding
race も吸収する。

queue は ring buffer (深さ 8、1 entry 16B)。peripheral 側は
`CONFIG_ZMK_USB=n` で `app/src/usb_hid.c` 自体が compile されない
ため無影響。FLASH 数百B / RAM ~200B (dongle build) のオーバーヘッド。

**upstream PR**: [zmkfirmware/zmk#3384](https://github.com/zmkfirmware/zmk/pull/3384)
(`CONFIG_ZMK_USB_HID_REPLAY_ON_READY` の Kconfig gate + queue depth /
flush delay の Kconfig 化、default n)。merge され次第本 patch を畳む。
関連 issue: [zmkfirmware/zmk#2686](https://github.com/zmkfirmware/zmk/issues/2686)。

## パッチを追加するとき

1. `~/.cache/zmk-canon/cfgrepo/zmk/` で対象ファイルを編集
2. `git -C ~/.cache/zmk-canon/cfgrepo/zmk diff <path> > patches/zmk/<name>.patch`
3. `./scripts/build-zmk.sh` で適用 → ビルドが通ることを確認
4. 本 README に目的と upstream 化方針を追記
