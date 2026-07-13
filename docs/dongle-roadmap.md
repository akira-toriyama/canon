# Dongle (2.4GHz) ロードマップ

Cyboard Imprint を **dongle 中継構成**(USB ドングル = central / 左右半分 = peripheral)
で運用する作業の全体計画。複数セッションにまたがるため、状況・残タスク・
判断保留点をここに集約する。

最終ゴールは:
- **canon** に dongle 用 user-config を維持
- **Cyboard-DigitalTailor/zmk-keyboards** に `imprint_dongle` shield を上流化
- **zmkfirmware/zmk** に stale bond 自動回復のパッチを上流化

## 🔧 ペアリング復旧手順（NVS リセット後・キーボードが効かない時）

> **最重要**: imprint が唯一のキーボードなら、これをやる前に**別の USB キーボードを
> 用意**すること（リセット中〜復旧まで打てなくなる。Mac mini 等で本機しか無いと詰む）。
> そして **リセットボタン1回・USB 挿し直しでは bond は消えない**（再起動するだけ）。
> bond を消せるのは NVS wipe（RESET firmware）だけ。keymap に手動クリアキーは無い。

### ⚡ コピペ一発復旧（一人・マウスだけ／キーボードが打てなくても可）

> **Claude Code と一緒なら**: チャットに「**キーボード復旧**」とだけ伝えれば、
> 下の手順（まず A、ダメなら下記コマンド）を Claude が代行する。

まず下の **手順A（物理・PC 不要）** を試す。直らなければ Terminal を開き、
以下を**マウスで選択 → ペースト**（末尾改行込みで自動実行＝タイプ不要）。各スクリプトの
確認は `--yes` で飛ばすので、あとは**各デバイスをダブルタップでブートローダにするだけ**:

```sh
# 速い版（ビルド済 *_RESET.uf2 と通常版を焼くだけ）
cd /Volumes/workspace/github.com/akira-toriyama/canon && ./scripts/flash-reset.sh --yes && ./scripts/flash-watch.sh --yes
```

```sh
# 確実版（先に再ビルドしてから焼く。uf2 が古い/消えている時）
cd /Volumes/workspace/github.com/akira-toriyama/canon && ./scripts/build-zmk.sh imprint --reset && ./scripts/build-zmk.sh imprint && ./scripts/flash-reset.sh --yes && ./scripts/flash-watch.sh --yes
```

焼き終わったら **手順A の順番（子機を先に広告 → 最後にドングル）で繋ぐ**。詳細は下記 A / B。

### A. まず試す（PC 操作不要・物理だけ／一度はこれで復活した）
左右がドングルと食い違っているだけなら、**繋ぎ直す順番**だけで直る:

1. ドングルを USB から**抜く**
2. 左右半分の**電源を入れて 10 秒待つ**（この間ずっと「誰でも繋いで」と広告する）
3. ドングルを USB に**挿し直す**（空の親が子を探しにいく）
4. **30〜60 秒、触らず待つ**（左右の両方とペアリング完了まで）
5. 左右それぞれ 1 キーずつ確認。片方だけ効くなら B でその半分だけやり直す

### B. A でダメ＝bond が非対称に壊れている → 全消去してやり直す
（ターミナルが要る。マウス + スクリーンキーボードでも可）

1. `./scripts/build-zmk.sh imprint --reset` と `./scripts/build-zmk.sh imprint`（両方ビルド）
2. `./scripts/flash-reset.sh` → 左・右・dongle を**ダブルタップ**でブートローダにして
   全部に RESET を焼く（NVS を**対称に**全消去）。**シングルタップは再起動だけ＝消えない**
3. `./scripts/flash-watch.sh` → 同様に通常版を焼く（左→右の順、dongle は XIAO 自動検出）
4. **A の手順（子機を先に広告 → 最後にドングルを挿す）で繋ぐ**。この順番が肝

### なぜこうなるか
dongle = BLE central / 左右 = peripheral。bond が残った子機は「昔の親 MAC だけ」に向けて
**directed 広告**する＝scanning 中の新しい親から見えない。片側だけ消える/部分ペアで
**非対称**になると沈黙する（`security failed (err 2)` / slot 予約失敗）。だから「リセット連打」
では永遠に直らない（同じ NVS を読み直すだけ）。`flash-*.sh` は imprint 専用（XIAO を見ると
`imprint_dongle` を焼く）＝**ist（別 repo の受信ドングル）の XIAO には使わない**。

### 自動回復（既に有効）と検討した予防策

**stale bond の自動回復は既に常時有効**。`patches/zmk/security-changed-auto-unpair.patch`
（gate 無し・`build-zmk.sh` が全ビルドに無条件適用＝下記「現状」✅）が、再接続時の
`BT_SECURITY_ERR_PIN_OR_KEY_MISSING`（＝非対称 stale bond）を検知して当該ピアを
`bt_unpair` → 切断 → fresh 再ペアへ自動誘導する。**よくある片側 bond 破綻は焼き直さず
自動回復する**（`CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISSING` は上流 #3385 の gate 案の
名前で canon には無く、canon は常時 ON。#3385 が merge されたら gate 運用へ移行）。

**`&bt BT_CLR` キーは不採用**（wedge には効かないと ZMK ソースで確認）。`&bt` は CENTRAL
locality で dongle 上でのみ実行され、押下が peripheral→central の BLE 経路に乗って初めて
走る。直したい局面＝BLE が wedge した状態ではキーが central に届かず無力。かつ peripheral
側の腐った bond は central の BT_CLR では消せない。確実な手動復旧は RESET firmware
（NVS wipe）のみ。

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
