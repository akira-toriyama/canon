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
# 注: 本 PR (capsule-corp 移行ベースライン) は chord pre-v0.2.0 を前提とし、
# L/R 区別しない device-independent な `ctrl/alt/shift/cmd` で記述する。
# chord 側 PR1 (ed1c032 `feat(core)!: side-specific modifier tokens`) で
# `rctrl/lcmd/...` トークンが追加されたが、未リリース。chord v0.2.0 着地後の
# follow-up PR で `rctrl + ralt + rshift` 等へ置換し ZMK 右側修飾子チョード
# 専用に厳格化する（"設計意図復活"）。
# 現状の影響: 左 modifier 3 個＋同キーの偶発で発火しうるが、実用上は稀。
export ULTRA_LL="ctrl + alt + shift"      # ULTRA_LL: ALT+SHIFT+CTRL (CMD なし)
export MIRACLE_LM="ctrl + cmd + shift"      # MIRACLE_LM: CMD+SHIFT+CTRL (ALT なし)
export MEGA_RM="ctrl + cmd + alt"        # MEGA_RM: CMD+ALT+CTRL  (SHIFT なし)
export WONDER_RR="cmd + alt + shift"       # WONDER_RR: CMD+ALT+SHIFT (CTRL なし)
