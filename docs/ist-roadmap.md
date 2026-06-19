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
| I1 | ist firmware を canon に統合 | canon | ☐ TODO（**要 GO**） | west(module) + ist keymap/conf + build.yaml に ist target + build-zmk.sh group(all/imprint/ist) + docs。**C6 と協調**（同じ canon docs を触る） |
| I2 | ist で vkey 有効化 | canon | ☐ TODO | **I1 後**。共有 vkey dtsi + `zip_btn_remap` bindings に `&vkey` + gen-vkey-aliases.py が ist keymap も走査 + id single-source 整理 + chord 側 alias |
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

- **vkey id single-source**: 今 gen-vkey-aliases.py は imprint.keymap のみ。ist も出すなら両 keymap 走査 + id 分離。
- `zip_btn_remap` が `&vkey` の press/release を `&kp` 同様に駆動するか → **初回ビルド/実機で確認**。
- **zmk-ble-hid-host は WIP（M4+ 未）** → main 追従で結合し上流変化に追従（canon CI が早期検知）。
- module + Cyboard module + patches/zmk/* の三者同居 build が green か → CI で確認。

## 更新ログ

- 2026-06-19: 設計確定（canon 同居 / 3 profile セレクタ / ist で vkey 可）。feasibility 調査を転記し
  本 roadmap 作成。全タスク TODO・**I1 は user GO 待ち**。
