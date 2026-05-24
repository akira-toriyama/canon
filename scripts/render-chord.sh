#!/usr/bin/env bash
#
# chord 設定の生成・反映エントリポイント。
#
#   ./scripts/render-chord.sh
#
# 実装は持たない。chord アセット（config.tmpl 等）と同居させるため、本体は
# host/chord/render.sh に置き、ここはそれを実行するだけの薄いラッパ
# （scripts/ にエントリポイントを統一する目的）。
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO/host/chord/render.sh" "$@"
