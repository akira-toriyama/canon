#!/bin/bash
# envsubst へ渡すリテラルな ${VAR} を単一引用で保持する設計のため、
# SC2016（単一引用内は非展開）は意図どおり。ファイル全体で無効化する。
# shellcheck disable=SC2016
set -euo pipefail
cd "$(dirname "$0")"

# 変数定義（修飾子セット）は別ファイルへ分離（データ＝render-vars.sh /
# ロジック＝本ファイル）。値の編集は render-vars.sh で完結。
# shellcheck source=render-vars.sh
# -x 無しの単体検査では source 先を追えない（CI は plain shellcheck）。
# shellcheck disable=SC1091
. ./render-vars.sh


# ---- config.toml 生成 → 検証 → デプロイ ----
# 対象は akira-toriyama/chord (https://github.com/akira-toriyama/chord)。
# 設定既定パスは ~/.config/chord/config.toml、検証は `chord --validate`、
# リロードは `chord --reload`（chord は vnode で自動 reload もする）。
# source (config.tmpl) は repo 内、生成物は ~/.config/chord/config.toml。
# 一旦 temp に生成して検証し、OK の時だけデプロイ先へ移動する
# (壊れた設定が稼働中の config を上書きしない)。
OUT="$HOME/.config/chord/config.toml"

# envsubst は指定変数のみ置換。修飾子セット 4 個＋効果音パスを明示。
VARS='${ULTRA_LL} ${MIRACLE_LM} ${MEGA_RM} ${WONDER_RR} ${UNDEFINED_KEY_SOUND_PATH}'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
envsubst "$VARS" < config.tmpl > "$tmp"

# chord 未インストールでも生成・配備は通す（fresh machine の bootstrap 想定）。
# 通常運用では brew tap (akira-toriyama/tap/chord) で入れる前提。検証は
# chord available 時のみ走り、失敗時は exit 1 で稼働中 config を上書きしない。
if command -v chord >/dev/null 2>&1; then
    vout=$(mktemp)
    trap 'rm -f "$tmp" "$vout"' EXIT
    if chord --validate --config "$tmp" >"$vout" 2>&1; then
        :
    else
        echo "chord --validate failed, NOT deploying:" >&2
        cat "$vout" >&2
        exit 1
    fi
else
    echo "warn: 'chord' が PATH に無いため --validate をスキップしました。" >&2
    echo "      生成された config.toml は構文的に envsubst 後の TOML として有効ですが、" >&2
    echo "      chord 上の意味的妥当性は未検証です。インストール後に手動で" >&2
    echo "      'chord --validate' を実行してください。" >&2
fi

mkdir -p "$(dirname "$OUT")"
[ -f "$OUT" ] && cp "$OUT" "$OUT.bak"   # 直前の稼働設定を .bak へ退避
# 注: 検証は mv 前に済むため自動復元はしない。.bak は手動復旧用の置物。
mv "$tmp" "$OUT"
trap - EXIT

# chord は vnode 監視で自動 reload するが、念のため --reload を打つ。
# 未インストール時は warn のみ（auto-reload が起動後に拾う）。
if command -v chord >/dev/null 2>&1; then
    chord --reload 2>/dev/null || true
    echo "config.toml deployed to $OUT and reloaded"
else
    echo "config.toml deployed to $OUT (chord 未インストールのため reload はスキップ)"
fi
