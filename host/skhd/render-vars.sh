# shellcheck shell=bash
# host/skhd/render-vars.sh
#
# render.sh が冒頭で source する「変数定義のみ」のファイル（データ／ロジック
# 分離）。単体実行しない（shebang 無し・実行ビット不要）。値の編集はこの
# ファイルだけで完結する。
#
# ここで export する変数は skhdrc.tmpl の ${VAR} 置換対象。X_* は render.sh が
# ${!X_@} から envsubst 対象 (VARS) を自動列挙するため、キーを増減してもここ
# だけで済む。X_ 以外の置換変数を増やす時は render.sh の VARS 固定列にも追加。

# ---- ZMKで定義したベースキー ----
export X_Q=0x0C
export X_W=0x0D
export X_E=0x0E
export X_R=0x0F
export X_T=0x11
export X_A=0x00
export X_S=0x01
export X_D=0x02
export X_F=0x03
export X_G=0x05
export X_Z=0x06
export X_X=0x07
export X_C=0x08
export X_V=0x09
export X_B=0x0B
export X_Y=0x10
export X_U=0x20
export X_I=0x22
export X_O=0x1F
export X_P=0x23
export X_H=0x04
export X_J=0x26
export X_K=0x28
export X_L=0x25
export X_N=0x2D
export X_M=0x2E
export X_1=0x53 # Lの右
export X_2=0x54 # UP_ARROW
export X_3=0x55 # DELETE
export X_4=0x56 # TAB

# ---- ZMKで定義したmodifier セット ----
export ULTRA_LL="rctrl + ralt + rshift"      # ULTRA_LL: RALT+RSHIFT+RCTRL (RGUI なし)
export MIRACLE_LM="rctrl + rcmd + rshift"      # MIRACLE_LM: RGUI+RSHIFT+RCTRL (RALT なし)
export MEGA_RM="rctrl + rcmd + ralt"        # MEGA_RM: RGUI+RALT+RCTRL  (RSHIFT なし)
export WONDER_RR="rcmd + ralt + rshift"       # WONDER_RR: RGUI+RALT+RSHIFT (RCTRL なし)

# ---- macOS 側の出力で使うキーコード ----
export BRACKET_OPEN=0x21   # [
export BRACKET_CLOSE=0x1E  # ]

# ---- 効果音 ----
# 4 修飾子セット下で「未バインドの全キー」を押した時のフィードバック音。
# 実バインド済みの組合せは render.sh の生成で自動除外（skhd.zig は重複
# binding をハードエラーにするため）。envsubst 対象ではないので export 不要。
#
# 効果音アセットは「横断資産」: skhd 以外 (rift のフォーカス通知等) からも
# 鳴らすため capsule-corp は実体を持たない。所有・配備は dotfiles(chezmoi)
# の責務（リポジトリ境界: 当 repo は入力パイプライン、環境側資産は dotfiles）。
# ここは配備先ディレクトリを参照するだけ。CAPSULE_SOUND_DIR で上書き可、
# 既定は XDG データディレクトリ配下。dotfiles 側で
#   <SOUND_DIR>/undefined-key.wav
# をイベント名規約で配置すること（未配置なら afplay 無音）。
SOUND_DIR="${CAPSULE_SOUND_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sounds}"
# 命名は dotfiles の規約に合わせる: <event>.wav・アンダースコア区切り
# （既存 window_focused.wav と同流儀。同一ディレクトリに混在するため）。
# render.sh が source して使う（上記のとおり export しない設計）。
# shellcheck disable=SC2034
SE_UNDEFINED="$SOUND_DIR/undefined_key.wav"
