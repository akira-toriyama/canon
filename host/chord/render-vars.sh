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
# chord v0.2.0 で side-specific 修飾子トークン (`rctrl/ralt/rshift/rcmd`/
# `lctrl/...`) が解禁された（PR1 `feat(core)!: side-specific modifier tokens`、
# ed1c032）。これにより ZMK 右側修飾子チョード専用の厳格マッチを表現できる。
# 移行ベースライン (PR #26) では device-independent な `ctrl/alt/shift/cmd` で
# 妥協していたが、本 PR で **設計意図 = 右側 modifier 限定** を復活させる。
# 効果: 通常のタイピングで `ctrl + alt + shift + X` を左側で偶発しても発火しない
# （ZMK ファームから届く右側 modifier セットだけが match）。
export ULTRA_LL="rctrl + ralt + rshift"      # ULTRA_LL: RALT+RSHIFT+RCTRL (RCMD なし)
export MIRACLE_LM="rctrl + rcmd + rshift"    # MIRACLE_LM: RCMD+RSHIFT+RCTRL (RALT なし)
export MEGA_RM="rctrl + rcmd + ralt"         # MEGA_RM: RCMD+RALT+RCTRL  (RSHIFT なし)
export WONDER_RR="rcmd + ralt + rshift"      # WONDER_RR: RCMD+RALT+RSHIFT (RCTRL なし)
