## 概要

<!-- 何を・なぜ。関連 issue があれば #番号 -->

## 種別

<!-- 該当を残す（semver は docs/commit-convention.md） -->

- [ ] feat（機能追加 / minor）
- [ ] fix・perf（修正・改善 / patch）
- [ ] breaking（`!` / BREAKING CHANGE / major）
- [ ] その他（docs / ci / chore / build / refactor — bump なし）

## チェックリスト

- [ ] コミットは gitmoji + Conventional Commits 準拠（`<:gitmoji:> type(scope): subject`）
- [ ] keymap / behavior を変更した → ローカルビルド成功（`./scripts/build-zmk.sh`）
- [ ] `config/eiji_macros.dtsi` を変更した → `python3 scripts/gen-eiji-drawer-map.py` を実行しコミット済（verify-eiji-sync 対策）
- [ ] 生成・ツール管理ファイル（`keymap_drawer.config.yaml` の自動生成域 / `keymap-drawer/*` / `config/imprint.json`）を手編集していない
- [ ] 必要なら docs / CLAUDE.md を更新
- [ ] CI（build / commit-lint / shellcheck / draw / verify-eiji-sync）が緑

## 動作確認

<!-- 実機フラッシュなど、確認した内容 -->
