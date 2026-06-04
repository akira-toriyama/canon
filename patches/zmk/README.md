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

upstream PR の際は `CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISMATCH` 等の
Kconfig flag で gate する想定。

## パッチを追加するとき

1. `~/.cache/zmk-canon/cfgrepo/zmk/` で対象ファイルを編集
2. `git -C ~/.cache/zmk-canon/cfgrepo/zmk diff <path> > patches/zmk/<name>.patch`
3. `./scripts/build-zmk.sh` で適用 → ビルドが通ることを確認
4. 本 README に目的と upstream 化方針を追記
