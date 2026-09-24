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

### `split-battery-source-bounds.patch`

`app/src/split/central.c` の battery event 分岐に `source` の範囲検査を足す。upstream は
読み出し側 (`zmk_split_central_get_peripheral_battery_level`) でしか範囲を見ておらず、
書き込み `peripheral_battery_levels[source] = …` は無検査。`split_central_disconnected()` は
`peripheral_slot_index_for_conn()` の戻り値をそのまま uint8_t の `source` に入れるため、
slot を持たない接続が切れると `-EINVAL` が **234** になり、2 byte の配列の 234 byte 先へ
0 を書く (imprint_dongle の実ビルドでは BLE controller の ECC 鍵領域に着弾する)。
`split_central_connected()` と違い `BT_CONN_ROLE_CENTRAL` の filter が無いので、dongle 自身の
BLE 接続 (HOG で繋いだ phone 等) が切れるだけで到達する。

この分岐は `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING` 配下で、canon が
2026-09-24 に同 Kconfig を `config/imprint_dongle.conf` で有効化するまで compile されて
いなかった。**有効化と同じ PR で塞ぐ**。

**upstream PR**: 未提出。vkey #3390 とは独立の upstream バグ修正なので単独で出す。

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
- **upstream PR**: [zmk#3390](https://github.com/zmkfirmware/zmk/pull/3390)（提出済み・レビュー待ち。
  `CONFIG_ZMK_HID_VKEY` default-off で汎用化）。**merge されるまで本 patch は維持する**（canon は
  upstream に非依存。マージは難航しうる）。提出 diff・PR 本文・移行手順は
  [`docs/vkey-upstream-pr-draft.md`](../../docs/vkey-upstream-pr-draft.md)。
- 全フェーズ計画・検証ゲート: [`docs/vkey-roadmap.md`](../../docs/vkey-roadmap.md)。
- **Report ID `0x21` = split peripheral battery**（2026-09-24〜）。同じ `0xFF31` collection に
  `{source, level}` 2 byte の input report を同居させる。`source` = split peripheral の slot index
  （0/1・接続順で決まり左右固定ではない）、`level` = 0..100。切断時に central が流す `0` は
  firmware では落とさず素通し（host が「切断」と「0%」を区別する）。
  - 追加物: `app/src/split/bluetooth/central_battery_hid.c`（`zmk_peripheral_battery_state_changed`
    listener → `zmk_hid_split_battery_set` → `zmk_endpoint_send_split_battery_report`）、
    Kconfig `ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_HID`（default n・`depends on ZMK_USB`、
    `FETCHING` の配下）、`usb_hid.c` の GET_REPORT case と送出関数、`endpoints.c` の dispatcher。
    有効化は `config/imprint_dongle.conf` の `..._FETCHING=y` + `..._HID=y`。
  - **別 patch ファイルに分けない**: 0x21 の descriptor 項目は vkey hunk の post-image
    （`hid.h` の 0xFF31 collection）の内側にしか置けず、分けると warm tree で本 patch の
    reverse-check と forward-check が両方落ちて `build-zmk.sh` が `exit 1` する（2026-09-24 実測）。
    `docs/vkey-roadmap.md` Phase 1 の「1 つの patch に集約」と同じ裁定。
  - `zmk_endpoint_clear_reports` には**足さない**: あれは「押しっぱなしのキーを旧 endpoint に
    残さない」契約で、battery に held state は無い。足すと endpoint 切替のたび捏造の `{source, 0}` が飛ぶ。
  - **pending ring を一切使わない**: `zmk_usb_hid_send_split_battery_report()` は
    `zmk_usb_hid_send_report()` を経由せず、`USB_DC_SUSPEND` 等のときと ring に未送出が残って
    いる間は `-EAGAIN` で捨てる。理由は 2 つ。ring（8 深）は溢れると**最古**を捨てるので、
    誰も待っていない level が打鍵を押し出す。そして `zmk_usb_hid_send_report()` の
    `USB_DC_SUSPEND` 分岐は `usb_wakeup_request()` を呼ぶので、半体の残量変化や切断で
    **スリープ中の host が起きる**。
  - **`zmk_usb_is_hid_ready()` では止められない**（2026-09-24 に前提の誤りが判明し撤回）:
    `app/src/usb.c` は `USB_DC_SUSPEND` を `ZMK_USB_CONN_HID` に写し、`is_configured` は
    真のまま据え置くので、suspend 中も真を返す。
  - 捨てた値は**再送されない**。半体は % が変わった時だけ notify し、無操作 30 秒で
    サンプリング自体を止めるため、次の値は数時間先になりうる。よって listener は送出の
    **前**に `zmk_hid_split_battery_set()` でキャッシュし、GET_REPORT(0x21) が既知の最新値を
    返せるようにしている。
  - 上流 PR zmk#3390 の提出 diff（`docs/vkey-upstream-pr-draft.patch`）は vkey のみで、
    本 patch とは以後乖離する。merge 時の畳み方は同 draft 文書の注記を参照。

## パッチを追加するとき

1. `~/.cache/zmk-canon/cfgrepo/zmk/` で対象ファイルを編集
2. `git -C ~/.cache/zmk-canon/cfgrepo/zmk diff <path> > patches/zmk/<name>.patch`
3. `./scripts/build-zmk.sh` で適用 → ビルドが通ることを確認
4. 本 README に目的と upstream 化方針を追記
