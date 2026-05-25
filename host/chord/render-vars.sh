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

# ---- 未定義キー効果音アセットパス ----
# 4 修飾子セット下で未バインドの全キーを押した時の効果音 (chord v0.2.0 PR5 の
# `[[fallbacks]]` + `*` ワイルドカードで実装。config.tmpl 末尾参照)。
#
# 効果音アセットは「横断資産」: chord 以外 (rift のフォーカス通知等) からも
# 鳴らすため capsule-corp は実体を持たない。所有・配備は dotfiles(chezmoi)
# の責務（リポジトリ境界 = 当 repo は入力パイプライン、環境側資産は dotfiles）。
# ここは配備先を render 時に envsubst で埋め込むだけ。CAPSULE_SOUND_DIR で
# 上書き可、既定は XDG データディレクトリ配下。dotfiles 側で
#   <SOUND_DIR>/undefined_key.wav
# をイベント名規約で配置すること（未配置なら afplay 無音）。
export UNDEFINED_KEY_SOUND_PATH="${CAPSULE_SOUND_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sounds}/undefined_key.wav"
