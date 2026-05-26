# Security Policy

ZMK ファームウェア設定の個人リポジトリです。攻撃対象面は限定的ですが、
報告経路を明示します。

## 報告方法

公開 issue は使わず、**GitHub の非公開脆弱性報告**（リポジトリ
"Security" → "Report a vulnerability"）から連絡してください。

対象となりうる例:

- `scripts/` のスクリプトに起因するローカル権限・任意コード実行の問題
- GitHub Actions ワークフローの供給網リスク（third-party action 等）

ハードウェア／ファーム機能の不具合は通常の issue で構いません。

## 対応

単独メンテナンスのため即応は保証できませんが、妥当な報告には可能な
範囲で対応します。修正は通常リリース（[docs/commit-convention.md](docs/commit-convention.md)）
に含めます。
