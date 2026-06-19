# コミット規約とバージョニング

このリポジトリ（ZMK ファームウェア設定）は **gitmoji + Conventional Commits
併用**でコミットし、コミットメッセージから [git-cliff](https://git-cliff.org)
が semver を算出してリリースする。

## フォーマット

```
<gitmoji> <type>(<scope>)<!>: <subject>

<body 任意>

<footer 任意 / BREAKING CHANGE: ...>
```

- `<gitmoji>` … 先頭に gitmoji を 1 つ。`:sparkles:` のテキスト形式（grep 容易・
  bot の `:bento:` と整合）。例: `:bug:`。
- `<type>` … Conventional Commits の型（`feat` `fix` `perf` `refactor` `docs`
  `test` `build` `ci` `chore` `style` `revert`）。**semver はこの型で決まる**。
- `<scope>` … 任意。`keymap` `combos` `ci` 等。
- `!` … 破壊的変更。または footer に `BREAKING CHANGE: <説明>`。
- `<subject>` … 命令形・簡潔に。日本語可（既存履歴に合わせる）。

### 例

```
:sparkles: feat(keymap): EIJI レイヤーに矢印クラスタを追加
:bug: fix(combos): 左手 home-row combo の誤爆を修正
:zap: perf(build): build-zmk.sh の west update を差分のみに
:boom: feat(keymap)!: base レイヤーの数字段を全面再配置
:memo: docs: README にローカルビルド手順を追記
:wrench: chore: prettier 設定を追加
:bento: ci: keymap-drawer の SVG を更新   ← bot 自動コミット
```

## semver マッピング

型 → バージョン（git-cliff の Conventional 解釈、SemVer 準拠）:

| 変更 | 型 / マーカー | バージョン |
|---|---|---|
| 破壊的変更（muscle-memory を壊す配列変更・再 flash 非互換 等） | `<type>!` / `BREAKING CHANGE:` | **major** |
| 機能追加（新レイヤー・新ビヘイビア・新マクロ 等） | `feat` | **minor** |
| 不具合修正・性能改善 | `fix` / `perf` | **patch** |
| それ以外（`docs` `ci` `chore` `style` `test` `refactor` `build`） | — | **bump しない** |

gitmoji 自体の公式 semver は
<https://github.com/carloscuesta/gitmoji/blob/master/packages/gitmojis/src/gitmojis.json>
（`:boom:`=major / `:sparkles:`=minor / `:bug:` 等=patch / 多くは null）。
本リポジトリは **型を semver の正**とし、gitmoji は可読性と CHANGELOG 分類に使う
（両者が食い違う場合は型が優先）。

### bot コミットの扱い（重要）

[draw-keymap.yml](../.github/workflows/draw-keymap.yml) は keymap 変更のたび
`:bento:` で SVG を自動コミットする。これを版に含めると描画更新ごとに版が
上がるため、**`github-actions` 名義の bot コミットはバージョン算出と CHANGELOG
から除外**する（[cliff.toml](../cliff.toml) の commit_parsers で skip）。

## リリース手順（自動ドラフト → 手動 Publish）

リリースは [release.yml](../.github/workflows/release.yml)。**push:main で自動**に
git-cliff が次版を算出し「ローリングドラフト」Release を作成／更新する（この時点では
**タグを作らない**）。マージするほど下書きが育つ。

1. push:main ごとに自動でドラフトを更新（次版 = 前回 tag 以降の型から git-cliff が
   `--bumped-version` で算出。「bump しない」型のみ／前回 tag と同版なら何もしない）
2. ファームを実機確認し「いま切る」と決めたら **GitHub の Release ドラフトを手動 Publish**
3. Publish で初めて `vX.Y.Z` タグが作られ、build.yaml 全ターゲットの `*.uf2`
   （`imprint_left` / `imprint_right` / `imprint_dongle` / `ble_hid_host_receiver`）が添付される

`workflow_dispatch` の `dry_run=true` はドラフトを作らない完全プレビュー。
`main` 保護を尊重するため **CHANGELOG を main へ自動 push しない**（タグ
`refs/tags/*` は branch ルール対象外）。各版の変更履歴は GitHub Release の
ノートを正とし、`CHANGELOG.md` は必要時にローカル/通常 PR で更新する。

初期版は `v0.1.0`（[cliff.toml](../cliff.toml) の `initial_tag`）。

## ローカル検証フック（任意・低依存）

Node 等は不要。リポジトリ同梱の shell フックを有効化:

```sh
git config core.hooksPath scripts/hooks
```

`commit-msg` フックが gitmoji + Conventional 形式を検証する。CI（PR）でも
[commit-lint.yml](../.github/workflows/commit-lint.yml) が同じ規則で検証する。
