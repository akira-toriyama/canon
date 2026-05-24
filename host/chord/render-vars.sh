# shellcheck shell=bash
# host/chord/render-vars.sh
#
# render.sh が冒頭で source する「変数定義のみ」のファイル（データ／ロジック
# 分離）。単体実行しない（shebang 無し・実行ビット不要）。値の編集はこの
# ファイルだけで完結する。
#
# ここで export する変数は config.tmpl の ${VAR} 置換対象（envsubst）。
# render.sh の VARS 列に対応して全件渡される。

# ---- ZMKで定義したmodifier セット ----
# 注: chord (akira-toriyama/chord) は L/R 修飾子を区別しない（CGEventTap が
# device-independent flag を扱うため rctrl/ralt/rshift/rcmd トークンが無く、
# ctrl/opt/alt/shift/cmd/fn/hyper に丸まる）。ZMK 側は右側修飾子を送るので
# 動作はするが、設計意図（"ZMK 専用チョードのみ反応"）は厳密には保たれない。
# 実用上、左 modifier 3 個＋同キーを偶発で押すケースは非常に稀。
export ULTRA_LL="ctrl + alt + shift"      # ULTRA_LL: ALT+SHIFT+CTRL (CMD なし)
export MIRACLE_LM="ctrl + cmd + shift"      # MIRACLE_LM: CMD+SHIFT+CTRL (ALT なし)
export MEGA_RM="ctrl + cmd + alt"        # MEGA_RM: CMD+ALT+CTRL  (SHIFT なし)
export WONDER_RR="cmd + alt + shift"       # WONDER_RR: CMD+ALT+SHIFT (CTRL なし)
