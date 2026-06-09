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
| 5a | 右トラックボールの dongle 経由 forward (マウス) | ✅ merged (#37) |
| 5b | 左トラックボールの dongle 経由 forward (スクロール) | ✅ merged (#38) |
| 6 | RGB underglow の再有効化 | ⬜ 未着手 |

実機検収済み: dongle (XIAO BLE) を PC に挿し、左右両半分のキー入力 +
右トラックボール(マウス) + 左トラックボール(スクロール)が USB HID
として届く。bond は NVS 永続化されて切断→再接続でも復帰する。

## 残タスク(upstream 別)

**最終目標: 関連リポジトリへ PR を出してマージしてもらうこと**。
canon 内の作業は「PR マージまでの中継」として運用する。

### canon 内で完結

- ✅ **ZMK パッチ管理(B案)**: `patches/zmk/security-changed-auto-unpair.patch`
  を repo 管理化、`scripts/build-zmk.sh` がビルド時に冪等適用する。
  詳細は [`patches/zmk/README.md`](../patches/zmk/README.md)。
  upstream(C案)がマージされたら本 patch ディレクトリごと畳む。
- **Phase 6: RGB**: `config/imprint_dongle.conf` の `ZMK_RGB_UNDERGLOW=n`
  を見直し。dongle に LED 無しなので peripheral 側のみ復活が現実的。
  ユーザー個人は RGB を常時 off で運用しており実機検証手段が無いため
  優先度低。
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
    mock kscan、左右トラックボール用 input-split listener 群。
- **upstream `imprint.dtsi` の chosen タイポ修正**: `zmk,matrix_transform`
  (underscore) で書かれていて user keymap の hyphen 上書きが効かない。
  ついでに直す価値あり。
- **左トラックボール用 input-split ノードの上流化**: Phase 5b で canon
  に追加した `trackball_central_split` (reg=1) を upstream `imprint.dtsi`
  に取り込んでもらう。これで canon の `imprint_left.overlay` から
  split_inputs extend を削除できる。
  - 命名: `trackball_central_split` 以外の方が分かりやすいかもしれない
    (例: `trackball_left_split`)。Cyboard maintainer と要相談。

### zmkfirmware/zmk に PR

- ✅ **stale bond 自動回復**: [zmkfirmware/zmk#3385](https://github.com/zmkfirmware/zmk/pull/3385)
  で `CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISSING` (default n) 付きで上流提案中。
  対応 patch: [`patches/zmk/security-changed-auto-unpair.patch`](../patches/zmk/security-changed-auto-unpair.patch)。
- ✅ **USB-HID resume の 1 打目消失 / 数打必要問題**:
  [zmkfirmware/zmk#3384](https://github.com/zmkfirmware/zmk/pull/3384) で
  `CONFIG_ZMK_USB_HID_REPLAY_ON_READY` (default n) + queue depth /
  flush delay の Kconfig 化付きで上流提案中。対応 patch:
  [`patches/zmk/usb-hid-prime-on-ready.patch`](../patches/zmk/usb-hid-prime-on-ready.patch)。
  関連 issue: [zmkfirmware/zmk#2686](https://github.com/zmkfirmware/zmk/issues/2686)。
- **(オプション) xiao_ble の MPU_ALLOW_FLASH_WRITE 警告**: xiao_ble の
  defconfig が NVS 必須設定を含んでおらず、user-config 側で個別に
  揃える必要がある。これは Zephyr 側の問題寄りなので、ZMK で
  ドキュメント追加するか、ZMK board variant (`xiao_ble//zmk`) 側で
  defconfig を補強するかが議論ポイント。

## ZMK source patch (out-of-tree)

**B案 完了**: `patches/zmk/*.patch` を repo 管理化し、
`scripts/build-zmk.sh` の docker bash 内で `west update` の後に冪等に
`git apply` する。詳細・追加時の手順は [`patches/zmk/README.md`](../patches/zmk/README.md)。
現状 2 patch: `security-changed-auto-unpair.patch` / `usb-hid-prime-on-ready.patch`。

**C案(upstream PR) 着手済**: 上記 2 patch を `zmkfirmware/zmk` に
[#3384](https://github.com/zmkfirmware/zmk/pull/3384) / [#3385](https://github.com/zmkfirmware/zmk/pull/3385)
で提案中。各 PR は maintainer の要望を先回りして Kconfig gate
(default n) 付きで作成済。merge されたら対応する patch を畳む
(build-zmk.sh の apply フックは patch ディレクトリが空になっても
無害なので最後に畳む)。

### 検討した代替案(参考)

- **A. ZMK を fork**: `config/west.yml` の zmk projects を fork に差し替え、
  fork にパッチを当てたブランチを置く。Cyboard が main 追従必須なのと
  同じ理由で、追随コストが継続発生するため不採用。
- **C 先行**: B を飛ばして PR 直行は merge 待ちで canon 運用が
  dongle 不安定のままなので不採用。
- 採用: **B → C** の二段(B で運用安定、並行で C を進める)。

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
