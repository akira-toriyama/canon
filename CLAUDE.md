# CLAUDE.md

Claude Code 向けのプロジェクト運用メモ。人間向けの概要は
[README.md](README.md) を参照。本ファイルは「壊しやすい点」と「正しい手順」に絞る。

## このリポジトリ

ZMK ファームウェア設定（[Cyboard Imprint](https://cyboard.digital/products/imprint)、
リポジトリルート = ZMK user-config）。

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
（Node ランタイム依存の常駐ツール等）をリポジトリに持ち込まない。git-cliff は
Actions / `npx` 経由で使い、リポジトリに Node 依存を追加しない。

## 壊しやすい点（最優先で意識する）

- **west マニフェストは [config/west.yml](config/west.yml)**（リポジトリ直下では
  ない）。topdir はリポジトリルート、`board=assimilator-bt`、
  `shield=imprint_left|imprint_right`。ボード/シールドは外部モジュール
  Cyboard `zmk-keyboards` 由来で、[boards/shields/](boards/shields/) が空なのは
  正常。
- **ZMK は `main` 追従必須・タグ固定しない**: Cyboard `zmk-keyboards@main` の
  `assimilator-bt` は新 Zephyr ハードウェアモデル(HWv2)を要求する。ZMK を
  タグ（例 `v0.3.0`）固定すると CI/ローカルとも `arch.cmake` で
  `Could not find ARCH=cyboard` となりビルド不能。ZMK 公式の版固定推奨より
  この依存を優先（[config/west.yml](config/west.yml) / build.yml は `@main`）。
- **単一ソース規約**: [config/eiji_macros.dtsi](config/eiji_macros.dtsi) が唯一の
  ソース。`keymap_drawer.config.yaml` の AUTO-GENERATED ブロックは
  [scripts/gen-eiji-drawer-map.py](scripts/gen-eiji-drawer-map.py) が生成し、
  [verify-eiji-sync.yml](.github/workflows/verify-eiji-sync.yml) が CI で厳密一致を
  検証する。マーカー間を手編集しない。変更は dtsi を直し
  `python3 scripts/gen-eiji-drawer-map.py` を再実行（stdlib のみ）。
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
- `scripts/`（+`scripts/hooks/`）は現規模に適切。これ以上分割しない。

## ビルド

- ローカル: `./scripts/build-zmk.sh`（Docker。依存は `~/.cache/zmk-canon`
  に永続化、冪等。`--update` / `--clean`、シールド指定可。出力 `firmware/`＝
  gitignore 済）。詳細は [scripts/build-zmk.sh](scripts/build-zmk.sh) 冒頭。
- CI: push で [build.yml](.github/workflows/build.yml)（ZMK 公式 reusable）。
- リリース: [release.yml](.github/workflows/release.yml) を **手動起動**
  （workflow_dispatch）。コミットから次版算出 → `vX.Y.Z` タグ → GitHub
  Release（git-cliff ノート＋`imprint_*.uf2`）。main 保護尊重で CHANGELOG は
  main へ自動 push しない。

## コミット規約（必須）

**gitmoji + Conventional Commits**: `<:gitmoji:> <type>(<scope>)<!>: <subject>`
semver は `type` で決まる（`feat`→minor / `fix`・`perf`→patch / `!`・
`BREAKING CHANGE:`→major / その他は bump しない）。完全な規約・semver 表・
bot 除外は **[docs/commit-convention.md](docs/commit-convention.md)** を参照
（設定 [cliff.toml](cliff.toml)）。

- ローカル検証フック: `git config core.hooksPath scripts/hooks`
- PR では [commit-lint.yml](.github/workflows/commit-lint.yml) が同規則で検証
- bot（`github-actions` 等）コミットは版算出・CHANGELOG から除外
- 例: `:sparkles: feat(keymap): 矢印レイヤーを追加` /
  `:bug: fix(combos): 誤爆を修正` / `:memo: docs: 手順を追記`

## エディタ

[.vscode/settings.json](.vscode/settings.json) で保存時 prettier（md/json/yaml
のみ。`.dtsi`/`.keymap`/`.conf`/`.sh`/`.py` は対象外）。

## レビュー / コスト方針（課金回避）

- **CI で Claude（課金 API）を使わない**。PR ゲートは無料の決定的チェックのみ
  （build / commit-lint / shellcheck / draw fail_on_error / verify-eiji-sync）。
- Claude レビューが必要なときは**手元でオンデマンド**起動（`/review`,
  `/ultrareview` 等）。CI に Claude 自動レビューを足さない（増分$0 を維持）。
- public repo のため GitHub Actions 実行は無料枠。課金 API を使う workflow を
  追加しないこと。

## Roadmap board (GitHub Projects)

この repo の issue は集約 Project「roadmap」(akira-toriyama #5・
https://github.com/users/akira-toriyama/projects/5)で管理。Claude もこれに従う:

- 新規 issue は **Inbox** 既定。off-board の open issue を残さない(迷子を作らない)。
- Status(single-select): `Inbox → Backlog → Ready → In Progress → Done` / `Icebox`=someday。Ready は 2〜3(WIP)。
- PR 本文に `Closes #N` を必ず書く → merge で issue 自動 close → 自動 Done。
- 詳細は Project の README。
