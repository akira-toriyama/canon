# ist 統合 Roadmap

> `zmk-mouse`（IST PRO トラックボール受信ドングルの ZMK ファーム）を **canon へ統合**し、
> imprint と並ぶ build product にする。さらに **ist でも vkey(vendor-HID) を使える**ようにする。
>
> **単一台帳。着手・完了・棚上げは必ずここへ反映（未達成を暗黙にしない）。**
> 関連: [vkey-roadmap.md](vkey-roadmap.md)（vkey 機構）/
> [review-followup-roadmap.md](review-followup-roadmap.md)（別系統の chord/canon 整備 C1–C7）。
> cross-repo 方針は他 roadmap と同じ: コード変更は各 repo の独立 PR、台帳更新は canon。

## 決定済みの設計（「ゆっくり議論」で確定）

- canon = **ZMK ファーム集約 repo**: `imprint` + `ist` の2 build product。
  chord(Swift デーモン) は別レイヤーのまま据え置き（ZMK ファームを混ぜない）。
- **「3 ビルド = all / imprint / ist」は 3 ディレクトリでも 3 build.yaml でもなく、
  `build.yaml` 1枚(=all) に対するセレクタ**として実装する:
  - **all** = build.yaml 全 entry。CI(push/PR/週次) と release の既定（通常これでOK。
    理由: ビルド時間差が小さい）。
  - **imprint / ist** = サブセット選択。ローカルは `build-zmk.sh` の group 指定、
    任意で CI に `workflow_dispatch` の `profile: all|imprint|ist` 入力＋matrix フィルタ1段。
  - canon の単一ソース原則（build.yaml 1枚／release.yml の drift 教訓）に従い定義は分割しない。
- ist で vkey: トラックボールのボタン → `&vkey <id>` → chord が vendor-HID で受ける。

## 調査結果（feasibility 確定・根拠）

- **zmk-mouse** = 単体 ZMK user-config（board `xiao_ble/nrf52840/zmk`, shield `ble_hid_host_receiver`）。
  実ロジックは module **zmk-ble-hid-host**（`zephyr/module.yml` 持ちの正規 west module。
  **WIP**: M0–M3 実機OK / M4+ dongle・customization 未）。BLE-HID central で IST PRO を受け USB 中継。
- board は canon の `imprint_dongle` と**同じ XIAO**。shield `ble_hid_host_receiver` は **module 提供**
  → canon 側に boards/ ローカルコピー不要。`config/ble_hid_host_receiver.keymap`(+ .conf) のみ取り込む。
- west: remote `akira-toriyama` + project `zmk-ble-hid-host@main` を追加（`import:` 無し＝
  Cyboard zmk-keyboards と manifest 衝突なし）。
- **ist で vkey は使える（確定）**:
  - vkey HID collection (`0xFF31` / report `0x20`) は `patches/zmk/vkey-report.patch` で
    **`CONFIG_ZMK_POINTING` guard の外＝常在** → patch 済ファームは USB に必ず vkey を出せる。
  - `zmk_endpoint_send_vkey_report()` は **USB 実装あり**（BLE HOG は意図的 descope）。ist は USB → OK。
  - **トリガ**: ist の input-processor `zip_btn_remap` は `bindings = <&kp A &kp B …>`＝
    **behavior の phandle 配列**。ここを `<&vkey 0x01 …>` に差し替えれば、ボタン押下が `&vkey` を
    起動 → 0x20 送出 → chord が読む。（pointing ボタン→keymap behavior の橋を module が既に持つ）
  - `zmk-build.yml` は全ターゲットに patches/zmk/* を適用 → **ist も vkey 自動で乗る**。
    `release.yml` は `*.uf2` 汎用 glob → ist の uf2 は**自動添付**（glob 変更不要）。

## タスク

| ID | 内容 | repo | 状態 | 前提 / メモ |
|----|------|------|------|------------|
| I1 | ist firmware を canon に統合 | canon | ▶ 進行中（[canon#74](https://github.com/akira-toriyama/canon/pull/74)） | core 完了・**CI で ist ビルド green**。残: docs(README ほか) + build-zmk.sh group。下記「引き継ぎ」参照 |
| I2 | ist で vkey 有効化 | canon | ▶ 実装完了・**ファームビルド green**（実機未検証） | 共有 `vkey_behavior.dtsi` + `zip_btn_remap` を `&vkey 0xA0..0xA3` + gen-vkey-aliases.py が両 keymap 走査（ist band 0xA0..0xBF 分離）+ alias 生成。残=実機（user hw）+ chord 貼り込み（chezmoi=user）。下記「I2 実施メモ」 |
| I3 | ist を main 保護 ruleset の required check へ | canon | ☐ TODO（**要 user 承認**） | ruleset 16483994 変更。branch protection = 明示承認。**C5 と batch** |

### I1 詳細
1. `config/west.yml`: remote `akira-toriyama` + `zmk-ble-hid-host@main`。
2. `config/`: `ble_hid_host_receiver.keymap`(+ `.conf`) を zmk-mouse から取り込み（shield は module 提供）。
3. `build.yaml`: `- board: xiao_ble/nrf52840/zmk / shield: ble_hid_host_receiver`（+ logging variant は任意）。
4. `scripts/build-zmk.sh`: group ショートカット all|imprint|ist（既存の shield 指定の上に薄く）。
5. docs: CLAUDE.md の位置づけ・「壊しやすい点」・build target 数、README、glossary を
   「imprint + ist の ZMK ファーム集約」へ。→ **C6（docs ドリフト）をここで一括**。
6. 検証: canon CI で ist target が green（module + Cyboard + patch の三者同居を確認）。

### I2 詳細
1. `&vkey` behavior 定義（`imprint_behaviors.dtsi` の vkey ノード）を共有 dtsi に切り出し、
   imprint と ist の両 keymap で include。
2. ist keymap の `zip_btn_remap` の `bindings` を `&vkey <id>` に（割り当てたいボタンだけ）。
3. `gen-vkey-aliases.py`: imprint.keymap に加え ist keymap も走査。**id 空間の衝突回避**（分離 or 意図的共有）。
4. chord 側 `[v-key-aliases]` に ist の id→alias を追加（chezmoi 運用は別管理）。
5. 検証: 実機で ist のボタン → chord がその vkey を受信。

## 詰める点 / 未確定（着手時に解消）

- ~~**vkey id single-source**: 今 gen-vkey-aliases.py は imprint.keymap のみ~~ → **✅ 解消（I2）**: 両 keymap
  走査。ist は input-processor の codes↔bindings から alias 名を導出（code が名前の源＝二重管理なし）。
  id は ist 予約帯 `0xA0..0xBF`（imprint と分離）+ 跨ぎ衝突検出を gen-vkey-aliases.py に追加。
- ~~`zip_btn_remap` が `&vkey` の press/release を `&kp` 同様に駆動するか~~ → **✅ ビルドで解決（I2）**: ist
  firmware が `&vkey 0xA0..0xA3` を DT 解決しビルド green。behavior/HID 送出 symbol も ist `.elf` に存在
  （下記メモ）。**press/release の実 wire は実機で最終確認**（user hw、module の >5 ボタン publish は M4+ WIP）。
- **zmk-ble-hid-host は WIP（M4+ 未）** → main 追従で結合し上流変化に追従（canon CI が早期検知）。
- ~~module + Cyboard module + patches/zmk/* の三者同居 build が green か~~ → **✅ CI green 確認済（canon#74）**。

## I2 実施メモ / GOTCHA（ブランチ `feat/i2-ist-vkey`）

**実装（このPR）**:
- ✅ **共有 `config/vkey_behavior.dtsi`**（`&vkey` behavior ノードの唯一ソース）。imprint は
  `imprint_behaviors.dtsi` 経由、ist は `ble_hid_host_receiver.keymap` に新設した `behaviors {}` から `#include`。
- ✅ ist `zip_btn_remap` の bindings を `<&kp A..D>` → `<&vkey 0xA0 0xA1 0xA2 0xA3>`
  （INPUT_BTN_5/6 + tilt L/R）。
- ✅ `scripts/gen-vkey-aliases.py` を**両 keymap 走査**へ拡張。imprint=層/位置レンジ復号（不変・出力 byte 同一）、
  ist=codes↔bindings zip で `IST_BTN5/BTN6/TILT_L/TILT_R` を導出。**予約帯 0xA0..0xBF 検証 + 跨ぎ衝突検出 +
  C コメント除去**（ist keymap 冒頭の例ノードを拾わない）。`config/vkey-aliases.toml` に ist 節 4 行を追記。
- ✅ `verify-vkey-sync.yml` の paths に `config/ble_hid_host_receiver.keymap` 追加。CLAUDE.md 単一ソース規約を両
  keymap + 共有 dtsi + band 分離へ更新。`.gitignore` に `__pycache__/`。
- ✅ **draw 修正（I1 残のバグ回収）**: `Draw keymap` workflow は I1 で ist keymap 追加以降 **main で red**
  だった（keymap-drawer が `config/*.keymap` を自動探索し、物理キー無しの `ble_hid_host_receiver` で
  "physical layout could not be found"）。draw は required check ではないため I1 は red のままマージ。
  → `draw-keymap.yml` に `keymap_patterns: config/imprint.keymap` を設定し ist を描画対象外に（受信
  ドングルは描くものが無い）。**main の draw も green に戻る**。

**ビルド検証（Docker `build-zmk.sh ble_hid_host_receiver`, green）**:
- `ble_hid_host_receiver.uf2` 生成（FLASH 25.68%）。ist `.elf` に `behavior_vkey_driver_api` /
  `zmk_hid_vkey_set|clear` / `zmk_endpoint_send_vkey_report` / `zmk_usb_hid_send_vkey_report` /
  `CONFIG_ZMK_BEHAVIOR_VKEY=1`、ベンダー記述子 `06 31 FF 09 01 A1 01 85 20…` を確認。
  → ist は **central（非 split）ゲート真**で behavior をコンパイル、USB 送出経路も在。
- 🔴 **GOTCHA（当初の暫定対処。真因は I1-tail で別途修正）**: `Invalid SHIELD: ble_hid_host_receiver` が出て
  当時は **`build-zmk.sh --update`** で回避した。真因は「cache が古い」ではなく **build-zmk.sh の rsync
  `--delete` が `zmk-ble-hid-host` module の clone path を除外し忘れ、非 `--update` ビルドの度に module を
  削除していた**こと（I1-tail で `--exclude '/zmk-ble-hid-host/'` を追加して恒久修正）。修正後は `--update`
  無しでも ist がビルド可。

**残（I2 完了に必要・user 領域）**:
- ☐ **実機検証**: ist を焼き直し → トラックボールのボタン/チルト → chord が `vkey` を受信（press 毎 1 件 /
  release=0）。module の >5 ボタン publish は M4+ WIP のため、ボタン実発火はモジュール側進捗依存。
- ☐ **chord 貼り込み**: `config/vkey-aliases.toml` の ist 節（`IST_*`）を chord config の `[v-key-aliases]` へ
  + 各 id に action を割当（chord 側 **コード変更は不要**＝imprint と同一 wire。chezmoi re-add は user 運用）。

## I1 実施メモ / GOTCHA（canon#74 で判明）

- **三者同居 build は green**（patches: security/usb-hid-prime/vkey 全て「適用」OK、ist `ble_hid_host_receiver.uf2`
  + imprint 全ターゲット pass）。CI matrix も build.yaml の 4 ターゲット目を自動認識。
- **🔴 GOTCHA（重要）**: Cyboard `zmk-keyboards` の imprint shield `Kconfig.defconfig` が
  `config ZMK_RGB_UNDERGLOW default y` を **SHIELD ガード外**で宣言しており、canon の
  west workspace 全体（＝ ist ビルドにも）波及する。ist は `CONFIG_INPUT/POINTING` を引くため
  LED 依存が満たされ RGB が y になるが underglow ノードが無く `rgb_underglow.c` の `#error
  "A zmk,underglow chosen node must be declared"` で落ちた（imprint_dongle は INPUT 無しで
  依存未充足のため偶然回避）。**対処**: `config/ble_hid_host_receiver.conf` に
  `CONFIG_ZMK_RGB_UNDERGLOW=n` を明示（Cyboard 由来の stray default を上書き）。
  → **今後 imprint 以外の非 RGB ターゲットを足す時も同じ罠**。zmk-mouse 単体（Cyboard 無し）には無い問題。
- `-logging` 変種は canon の `zmk-build.yml` matrix awk が board/shield のみ抽出のため未対応（standard のみ採用）。

## 引き継ぎ（セッションまたぎ・I1 残 → I2 → I3）

**I1 で完了済（canon#74、ブランチ `feat/i1-ist-integration`）**:
- ✅ `config/west.yml`（remote akira-toriyama + module zmk-ble-hid-host@main）
- ✅ `config/ble_hid_host_receiver.{keymap,conf}`（zmk-mouse から byte-exact ＋ RGB=n 上書き）
- ✅ `build.yaml`（4 ターゲット目）／ ✅ CI ist green
- ✅ docs: CLAUDE.md（scope/壊しやすい点/build pipeline/release モデル）＋ glossary（board/shield/build target/.uf2）

**I1 残**（`chore/i1-tail-ist` で回収）:
- ✅ README / README.en に ist を最小言及（build 対象 4 つ + group 例。**user 主体**ゆえ最小ファクトのみ、intro/図/構成は不変）。
- ✅ `scripts/build-zmk.sh` に group ショートカット `all|imprint|ist`（build.yaml の shield 名から都度引く＝ハードコード無し）。
- ✅ glossary mermaid（board/shield/uf2 を ist 込みへ）/ glossary に **vkey 項目**を追加。
- ✅ **🔴 build-zmk.sh rsync バグ修正（I1 で混入）**: `zmk-ble-hid-host` module は west が `cfgrepo/zmk-ble-hid-host/`
  へ clone するが、build-zmk.sh の `rsync --delete` 除外リストが**この path を漏らしていた** → 非 `--update`
  ビルドの度に module が消え `Invalid SHIELD: ble_hid_host_receiver`。I1 で west.yml/build.yaml に module を
  足した時に除外を追従し忘れたのが根因（＝下の「I2 GOTCHA で --update が要った」本当の理由）。
  → `--exclude '/zmk-ble-hid-host/'` を追加。以後 ist も cache 再利用で普通にビルド可。
- ☐ `-logging` 変種を入れるなら zmk-build.yml matrix awk を cmake-args/artifact-name 対応に拡張（**別タスク・任意**、未着手）。

**I2 = ist で vkey — ✅ 実装完了（ブランチ `feat/i2-ist-vkey`、ファームビルド green）**:
詳細・成果物・GOTCHA は上記「I2 実施メモ / GOTCHA」。残は **実機検証** と **chord 貼り込み**（共に user 領域）
で、同メモ末尾「残」に集約。id single-source（両 keymap 走査 + band 分離 + 衝突検出）も同 PR で解消済。

**I3 = ist を required check へ**: ruleset 16483994 に
`build / Build (xiao_ble/nrf52840/zmk, ble_hid_host_receiver)` を追加（**branch protection = user 承認**、C5 と batch）。

## 更新ログ

- 2026-06-19: 設計確定（canon 同居 / 3 profile セレクタ / ist で vkey 可）。feasibility 調査を転記し
  本 roadmap 作成。全タスク TODO・**I1 は user GO 待ち**。
- 2026-06-19: **I1 着手（GO 済）→ ▶ 進行中（canon#74）**。core 統合（west module / keymap+conf /
  build.yaml 4 ターゲット目）完了、**CI で ist ビルド green**（三者同居 OK）。GOTCHA = Cyboard の
  stray `RGB_UNDERGLOW default y` を `CONFIG_ZMK_RGB_UNDERGLOW=n` で上書き。docs は CLAUDE.md +
  glossary 済。残（README / build-zmk.sh group / vkey glossary）と I2/I3 は上記「引き継ぎ」に集約。
- 2026-06-19: **I2 実装（ブランチ `feat/i2-ist-vkey`）→ ▶ ファームビルド green**。共有 `vkey_behavior.dtsi` +
  ist `zip_btn_remap` を `&vkey 0xA0..0xA3` + gen-vkey-aliases.py 両 keymap 走査（ist band 0xA0..0xBF 分離・
  跨ぎ衝突検出）+ vkey-aliases.toml / verify-vkey-sync paths / CLAUDE.md 更新。`build-zmk.sh --update
  ble_hid_host_receiver` で ist firmware + vkey symbol/記述子を確認。残=実機検証 + chord 貼り込み（user 領域）。
  詳細は「I2 実施メモ / GOTCHA」。
