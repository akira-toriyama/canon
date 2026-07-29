# CLAUDE.md

Claude Code 向けのプロジェクト運用メモ。人間向けの概要は
[README.md](README.md) を参照。本ファイルは「壊しやすい点」と「正しい手順」に絞る。

## このリポジトリ

自分の **ZMK ファーム repo**（リポジトリルート = ZMK user-config）。1 製品:

- **imprint**: [Cyboard Imprint](https://cyboard.digital/products/imprint) キーボード
  （board=assimilator-bt / shield=imprint_left・imprint_right、board=xiao_ble/nrf52840/zmk /
  shield=imprint_dongle）。

※ ist（トラックボール受信ドングル）は 2026-07-13 に canon から分離し、別 repo
（`zmk-ble-hid-host`）へ移した。canon には keymap も build target も残っていない。

## 用語

UI / 設定 / コード上の呼び名は [`docs/glossary.md`](docs/glossary.md) に従う
— 正規名（`keymap`, `layer`, `behavior`, `combo`, `macro`, `board`,
`shield`, `build target`, `host bridge`, …）のみを使い、`Don't call it:`
側の同義語は使わない。用語の追加・改名はコード変更と **同一 PR で**
このファイルへ反映する。


macOS 側ホストブリッジは独立リポジトリ
[`chord`](https://github.com/akira-toriyama/chord)（Swift 6 / CGEventTap
デーモン、`~/.config/chord/config.toml` 駆動）。本リポジトリは ZMK 側
（キーマップ・ファーム）のみを扱う。

設計思想は **低依存**（Python は stdlib のみ、他は shell）。重量級ツールチェーン
（Node ランタイム依存の常駐ツール等）をリポジトリに持ち込まない。リリースの
版・ノートは glyph（fleet 共通の Go バイナリ。Actions が checksum 検証つき
composite で導入）が算出し、リポジトリ側に設定も依存も持ち込まない。

## 壊しやすい点（最優先で意識する）

- **west マニフェストは [config/west.yml](config/west.yml)**（リポジトリ直下では
  ない）。topdir はリポジトリルート。外部モジュールは Cyboard `zmk-keyboards`
  1 つ（imprint の assimilator-bt board + imprint_left/right shield）。
  [boards/shields/](boards/shields/) のローカル shield は **`imprint_dongle` のみ**
  （他は module 由来）＝空ではない。board/shield の一覧（all ビルド）は
  [build.yaml](build.yaml) が唯一のソース。
- **ZMK は `main` 追従必須・タグ固定しない**: Cyboard の `assimilator-bt`（HWv2 版）は
  新 Zephyr ハードウェアモデルを要求する。ZMK を
  タグ（例 `v0.3.0`）固定すると CI/ローカルとも `arch.cmake` で
  `Could not find ARCH=cyboard` となりビルド不能。ZMK 公式の版固定推奨より
  この依存を優先（[config/west.yml](config/west.yml) / build.yml は `@main`）。
- **Cyboard `zmk-keyboards` は `main` でなく `zephyr-4.1` ブランチを追う**: 2026-07-07 に
  Cyboard が **main の意味を変えた**（main = ZMK `v0.3.0` pin + `assimilator-bt` を HWv1
  レイアウト `boards/arm/` へ差し戻し＝Studio 0.3.0 スタック）。canon は zmk@main
  （= Zephyr 4.1）なので main を引くと HWv1 board になり、cmake が soc Kconfig を作れず
  `Kconfig/soc/Kconfig.defconfig not found` で **assimilator-bt の 2 ターゲットだけ**落ちる
  （xiao_ble の imprint_dongle は通るので、部分的な赤に見えて紛らわしい）。HWv2 board
  （`boards/cyboard/assimilator-bt/board.yml`）は `zephyr-4.1` ブランチ側にあり、Cyboard
  自身が west.yml のコメントでそちらを案内している。
  ※ 2026-07-29 現在は zephyr-4.1 上の一時 SHA pin 中（上流入りした imprint_dongle
  shield がローカル同名 shield と衝突するため — 経緯と解除条件は
  [config/west.yml](config/west.yml) のコメントと t-zy1h）。
- **単一ソース規約（eiji）**: [config/eiji_macros.dtsi](config/eiji_macros.dtsi) が唯一の
  ソース。`keymap_drawer.config.yaml` の AUTO-GENERATED ブロックは
  [scripts/gen-eiji-drawer-map.py](scripts/gen-eiji-drawer-map.py) が生成し、
  [verify-eiji-sync.yml](.github/workflows/verify-eiji-sync.yml) が CI で厳密一致を
  検証する。マーカー間を手編集しない。変更は dtsi を直し
  `python3 scripts/gen-eiji-drawer-map.py` を再実行（stdlib のみ）。
- **単一ソース規約（vkey alias）**: [config/imprint.keymap](config/imprint.keymap) の
  `&vkey <id>` が唯一のソース。keymap は `&vkey` behavior ノードを
  [config/vkey_behavior.dtsi](config/vkey_behavior.dtsi) から `#include` する。
  生成物 [config/vkey-aliases.toml](config/vkey-aliases.toml)
  （host bridge [`chord`](https://github.com/akira-toriyama/chord) の `[v-key-aliases]` へ貼る用）は
  [scripts/gen-vkey-aliases.py](scripts/gen-vkey-aliases.py) が keymap を走査して id を復号し生成、
  [verify-vkey-sync.yml](.github/workflows/verify-vkey-sync.yml) が CI で照合する。id 空間は
  imprint が `0x01` / `0x10`–`0x8D`。**`0xA0`–`0xBF` は別 repo の ist 製品向けに予約**
  （chord の id→action はホスト単位で 1 つの名前空間＝再利用すると ist のボタンが誤爆する。
  `decode()` が構造的に拒否する）。
  `config/vkey-aliases.toml` を手編集しない。id を変えるときはキーマップを直し
  `python3 scripts/gen-vkey-aliases.py` を再実行（stdlib のみ）。これでキーマップ↔chord
  config の id 二重管理を排除する（chord 側への貼り込み＝chezmoi 運用は別管理）。
- **生成/ツール管理ファイルを手で整形・コミットしない**（[.prettierignore](.prettierignore) で除外済）:
  `keymap_drawer.config.yaml`（gen スクリプト）、`keymap-drawer/imprint.{yaml,svg}`
  （draw-keymap の bot が生成・コミット）、`config/imprint.json`（ツールデータ）。
- **ネットワークボリューム**: 作業ツリーは `/Volumes/...`。リポジトリ直下で
  `west update` しない（重い・汚す）。後述のスクリプトはキャッシュへ複製して
  ビルドする。
- **README は user 主体で執筆**。指示なく構成・文章を大幅に書き換えない。

## ディレクトリ構成（再構築しない）

現構成は健全。以下は ZMK / 上流ツールの制約で**移動不可**：

- `config/` `boards/` `zephyr/module.yml` `build.yaml` はリポジトリ**ルート**必須
  （ZMK reusable build と west の前提）。
- `keymap_drawer.config.yaml`（ルート）と `keymap-drawer/`（出力）の分離は
  caksoylar/keymap-drawer の既定どおりで**意図的**。"整理"して移動しない。
- `scripts/` は現規模に適切。これ以上分割しない。

## ビルド

- ローカル: `./scripts/build-zmk.sh`（Docker。依存は `~/.cache/zmk-canon`
  に永続化、冪等。`--update` / `--clean`、シールド指定可＝サブセット（例
  `imprint_left` だけ）。出力 `firmware/`＝
  gitignore 済）。詳細は [scripts/build-zmk.sh](scripts/build-zmk.sh) 冒頭。
- CI: PR / push:main で [build.yml](.github/workflows/build.yml)。実体は
  **canon ローカルの reusable [zmk-build.yml](.github/workflows/zmk-build.yml)**
  に委譲し、`patches/zmk/*`（vkey 等）と `patches/zephyr/*`（usb-hid-country-code）を
  当ててから build.yaml の全ターゲットを
  ビルドする（公式 reusable は patch を当てず &vkey 等が解決できないため差し替えた。
  背景は zmk-build.yml / [docs/vkey-roadmap.md](docs/vkey-roadmap.md)）。
- リリース: [release.yml](.github/workflows/release.yml)。**push:main で自動**に
  glyph が最後の v* タグ以降を squash-safe に歩いて次版とノートを算出し
  「ローリングドラフト」Release を upsert する（タグは作らない）。マージするほど
  下書きが育ち、**手動 Publish で初めてタグ生成 + `*.uf2` 添付**。
  `workflow_dispatch` の `dry_run=true` はドラフトを作らない完全プレビュー。

## コミット規約（必須）

**gitmoji-driven**: `<:gitmoji:>[(<scope>)][!] <subject>` — semver は gitmoji で
決まる。完全な規約・semver 表・除外規則は
**[CONTRIBUTING.md](https://github.com/akira-toriyama/.github/blob/main/CONTRIBUTING.md)** と `glyph rules` を参照。

- ローカル検証フック: clone ごとに一度 `glyph hook install`
- PR では [commit-lint.yml](.github/workflows/commit-lint.yml) が同規則で検証
- bot（`github-actions` 等）コミットは版算出・ノートから除外
- 例: `:sparkles:(keymap) 矢印レイヤーを追加` /
  `:bug:(combos) 誤爆を修正` / `:memo: 手順を追記`

## エディタ

[.vscode/settings.json](.vscode/settings.json) で保存時 prettier（md/json/yaml
のみ。`.dtsi`/`.keymap`/`.conf`/`.sh`/`.py` は対象外）。

## レビュー / コスト方針（課金回避）

- **CI で Claude（課金 API）を使わない**。PR ゲートは無料の決定的チェックのみ
  （build / commit-lint / shellcheck / draw fail_on_error / verify-eiji-sync /
  verify-vkey-sync）。
- Claude レビューが必要なときは**手元でオンデマンド**起動（`/review`,
  `/ultrareview` 等）。CI に Claude 自動レビューを足さない（増分$0 を維持）。
- public repo のため GitHub Actions 実行は無料枠。課金 API を使う workflow を
  追加しないこと。

## Claude Code

- 権限（WebFetch 許可ドメイン等）はローカルの `.claude/settings.json`（gitignore 対象）に置き、repo には commit しない（個人・マシン設定は共有しない方針・他 repo と統一）。
- 許可している WebFetch: `zmk.dev`（ZMK 公式ドキュメント）, `deepwiki.com`（repo 解説）＋ `WebSearch`。`karabiner-elements.pqrs.org` は未使用のため削除。
- 新マシンでは `.claude/settings.json` を手で再作成する（gitignore 対象＝clone で復元されない）。

## Roadmap board (GitHub Projects)

この repo の issue は集約 Project「roadmap」(akira-toriyama #5・
https://github.com/users/akira-toriyama/projects/5)で管理。Claude もこれに従う:

- 新規 issue は **Inbox** 既定。off-board の open issue を残さない(迷子を作らない)。
- Status(single-select): `Inbox → Backlog → Ready → In Progress → Done` / `Icebox`=someday。Ready は 2〜3(WIP)。
- PR 本文に `Closes #N` を必ず書く → merge で issue 自動 close → 自動 Done。
- 詳細は Project の README。
