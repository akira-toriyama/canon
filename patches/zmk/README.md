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

### `vkey-report.patch`

ベンダー定義 HID「オリジナルキー」(vkey) を追加する。Report ID `0x20` の
1 byte selector レポート (`0`=解放 / `1..255`=ID) を keyboard/consumer/mouse と
並ぶ独立 collection として `zmk_hid_report_desc[]` に足し、新 behavior
`&vkey <id>` (press で id 送出、release で 0 送出) を実装する。chord (macOS host
bridge) が IOHIDManager で受けて id→action にマップする想定。

- 触るファイル: `app/include/zmk/hid.h` (Report ID + descriptor + report 構造体),
  `app/src/hid.c` (state + set/clear/get), `app/src/usb_hid.c`
  (`zmk_usb_hid_send_vkey_report` + get_report_cb の 0x20 case),
  `app/src/endpoints.c` (`zmk_endpoint_send_vkey_report`),
  `app/include/zmk/{usb_hid,endpoints}.h`, 新規
  `app/src/behaviors/behavior_vkey.c` +
  `app/dts/bindings/behaviors/zmk,behavior-vkey.yaml`,
  `app/CMakeLists.txt` / `app/Kconfig.behaviors` (central gate 内で behavior 登録)。
- **USB のみ**。ドングル (central) が PC へ USB HID で送る経路に対応。BLE-HOG 直結は
  descope (`zmk_endpoint_send_vkey_report` の BLE 分岐は `LOG_WRN` + `-ENOTSUP`)。
- vkey レポートは既存 `zmk_usb_hid_send_report` を経由するので
  `usb-hid-prime-on-ready.patch` の resume queue を自動継承する。よって本 patch は
  `usb-hid-prime-on-ready.patch` の **後** に適用される必要があり、build-zmk.sh の
  `LC_ALL=C` 順 (s < u < v) で満たされる。
- descriptor の 16-bit usage page `0xFF31` は `HID_USAGE_PAGE()` が 1 byte に
  切り詰めるため raw long item `0x06,0x31,0xFF` でベタ書き。Input は単一の値
  フィールドなので `0x02` (Data,Variable,Absolute)。
- **upstream PR**: 未提出 (canon 固有機能。汎用化の見込みが立てば検討)。
- 全フェーズ計画・検証ゲート: [`docs/vkey-roadmap.md`](../../docs/vkey-roadmap.md)。

## パッチを追加するとき

1. `~/.cache/zmk-canon/cfgrepo/zmk/` で対象ファイルを編集
2. `git -C ~/.cache/zmk-canon/cfgrepo/zmk diff <path> > patches/zmk/<name>.patch`
3. `./scripts/build-zmk.sh` で適用 → ビルドが通ることを確認
4. 本 README に目的と upstream 化方針を追記
