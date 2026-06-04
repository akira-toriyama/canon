# Dongle (2.4GHz) ロードマップ

Cyboard Imprint を **dongle 中継構成**(USB ドングル = central / 左右半分 = peripheral)
で運用する作業の全体計画。複数セッションにまたがるため、状況・残タスク・
判断保留点をここに集約する。

最終ゴールは:
- **canon** に dongle 用 user-config を維持
- **Cyboard-DigitalTailor/zmk-keyboards** に `imprint_dongle` shield を上流化
- **zmkfirmware/zmk** に stale bond 自動回復のパッチを上流化

## 現状

| Phase | 内容 | 状態 |
|---|---|---|
| 1 | XIAO BLE 用空 shield + ビルド導線 | ✅ merged (#35) |
| 3a | dongle を BLE central 化 | ✅ merged (#35) |
| 3b | 右半分の peripheral 化(設定リセット運用) | ✅ merged (#35) |
| 4 | user keymap を dongle に適用 | ✅ merged (#35) |
| 4b | 左半分の peripheral 化 | ✅ merged (#35) |
| 5 | 左右トラックボールの dongle 経由 forward | ⬜ 未着手 |
| 6 | RGB underglow の再有効化 | ⬜ 未着手 |

実機検収済み: dongle (XIAO BLE) を PC に挿し、左右両半分のキー入力が
USB HID として届く。bond は NVS 永続化されて切断→再接続でも復帰する。

## 残タスク(upstream 別)

### canon 内で完結

- **ZMK パッチ管理**: 後述「ZMK source patch (out-of-tree)」参照。
  west update で消えないよう何らかの形で repo 管理化する。
- **Phase 5: トラックボール**: 左右の PMW3610 を peripheral から
  `zmk,input-split` で central(dongle) に forward。Phase 4b の
  `imprint_{left,right}.{conf,overlay}` で off にしている各ノードを
  再有効化し、dongle 側に listener を置く。
- **Phase 6: RGB**: `config/imprint_dongle.conf` の `ZMK_RGB_UNDERGLOW=n`
  を見直し。dongle に LED 無しなので peripheral 側のみ復活が現実的。
- **dongle 通常版(log なし)の運用切替**: 検証中は `imprint_dongle_log.uf2`
  を使ったが、通常運用は `imprint_dongle.uf2` に切り替える。

### Cyboard-DigitalTailor/zmk-keyboards に PR

- **`imprint_dongle` shield の上流化**: canon の
  `boards/shields/imprint_dongle/` を Cyboard 側に持ち込む。
  - canon に残っているのは upstream 不在の暫定実装なので、Cyboard 側に
    入ったら canon の同 shield を削除して upstream に切り替える。
  - Cyboard 側で imprint shield 配下のサブ variant にするか、独立 shield に
    するかは Cyboard maintainer と相談。
  - shield に取り込みたい設定の典型: `Kconfig.defconfig` の dongle 向け
    Kconfig 群、`imprint_dongle.overlay` のマトリクス transform 引用部、
    mock kscan。
- **upstream `imprint.dtsi` の chosen タイポ修正**: `zmk,matrix_transform`
  (underscore) で書かれていて user keymap の hyphen 上書きが効かない。
  ついでに直す価値あり。

### zmkfirmware/zmk に PR

- **stale bond 自動回復**: `app/src/ble.c` の `security_changed` で
  `BT_SECURITY_ERR_PIN_OR_KEY_MISSING` を受けたら `bt_unpair` して
  切断し、次の advert で fresh pair させる。
  - そのまま PR すると maintainer が「Kconfig flag で gate しろ」と
    言う可能性が高い。e.g. `CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISMATCH`。
  - 既存 issue / discussion を先に確認する。
- **(オプション) xiao_ble の MPU_ALLOW_FLASH_WRITE 警告**: xiao_ble の
  defconfig が NVS 必須設定を含んでおらず、user-config 側で個別に
  揃える必要がある。これは Zephyr 側の問題寄りなので、ZMK で
  ドキュメント追加するか、ZMK board variant (`xiao_ble//zmk`) 側で
  defconfig を補強するかが議論ポイント。

## ZMK source patch (out-of-tree)

現状 `~/.cache/zmk-canon/cfgrepo/zmk/app/src/ble.c` に以下を手動で当てて
ビルドした dongle が「stale bond 自動回復」を提供している。**このパッチは
canon repo に入っていない**ため、`west update` や clean cache で消える。

```c
// in security_changed(...)
if (!err) {
    LOG_DBG("Security changed: %s level %u", addr, level);
} else {
    LOG_ERR("Security failed: %s level %u err %d", addr, level, err);
    if (err == BT_SECURITY_ERR_PIN_OR_KEY_MISSING) {
        LOG_WRN("Stale bond detected, clearing and disconnecting");
        bt_unpair(BT_ID_DEFAULT, bt_conn_get_dst(conn));
        bt_conn_disconnect(conn, BT_HCI_ERR_AUTH_FAIL);
    }
}
```

対応案(どれかを選ぶ):

- **A. ZMK を fork**: `config/west.yml` の zmk projects を fork に差し替え、
  fork に上記パッチを適用したブランチを置く。Cyboard が main 追従必須
  なのと同じ理由で、追随コストは継続的に発生する。
- **B. in-repo patch**: `patches/zmk/security-changed-auto-unpair.patch` を
  置き、`scripts/build-zmk.sh` に `west update` 後の `git apply` を追加。
  CI もこのスクリプトを使えば共通。
- **C. upstream PR 先行**: 先に zmkfirmware/zmk に PR を投げて merge 待ち。
  merge までは canon 側の運用が dongle 不安定のままになる。

現実的には **B → C** の二段で進めるのが筋。B で時間を稼ぎながら C を進める。

## 学んだ詰まりどころ(忘れないよう)

- `xiao_ble` の Zephyr defconfig は flash/NVS 関連 Kconfig を含まない。
  `MPU_ALLOW_FLASH_WRITE=y` が無いと NVS 書き込みが silent fail し、bond
  保存が壊れる。assimilator-bt 側には board defconfig で入っているので
  気付きにくい。
- ZMK は board variant 機構(Zephyr 4.1〜)を導入済み。素の `xiao_ble` で
  なく **`xiao_ble/nrf52840/zmk`** を build.yaml で指定する必要がある。
  指定しないと CI が "Missing ZMK Compat" でエラー終了する。
- chosen のプロパティ名は **hyphen 表記** が ZMK の正規(`zmk,matrix-transform`)。
  upstream imprint.dtsi の underscore 表記は user keymap の上書きを
  ブロックする落とし穴。
- `scripts/build-zmk.sh` の rsync は `--delete` 無し。canon repo で削除した
  ファイルが `~/.cache/zmk-canon/cfgrepo/` に残り続け、`KEYMAP_FILE` 等の
  cmake cache 経由で古い参照が生きてしまう。挙動おかしい時は
  `--clean` してから再ビルド。
