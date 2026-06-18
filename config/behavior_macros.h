#pragma once

#include "layers.h"
#include "keypos.h"

// ====================================================================
// keymap で使う binding alias と behavior 生成マクロ
// ====================================================================

// --------------------------------------------------------------------
// keycode / binding alias
// --------------------------------------------------------------------
// 和英 (macOS LANGUAGE_*)
#define EIJI LANGUAGE_2
#define KANA LANGUAGE_1

// 親指下段 (TD = Thumb Down)。mod-tap: hold=修飾子 / tap=キー
#define TD_LL &mt LEFT_SHIFT RETURN
#define TD_LM &mt LEFT_COMMAND BACKSPACE
#define TD_RM &mt LEFT_ALT ESCAPE
#define TD_RR &mt LEFT_CONTROL SPACE

// 全 modifier (LGUI / LSFT / LCTL / LALT)。mod-morph の mods / keep-mods で使う
#define ALL_MODS (MOD_LGUI|MOD_LSFT|MOD_LCTL|MOD_LALT)

// DEFAULT_LAYER 左親指列で使う momentary layer 呼出。
// NAME : SYMBOL1 / SYMBOL2 / NUMBER / FUNCTION
#define MO_LAYER(NAME) &mo NAME##_LAYER

// 親指上段 (TU = Thumb Upper)。layer 起動 (+ LL/LM は修飾子も同時 hold)。
#define TU_LL &t_ll_ctrl       // T_LL_LAYER + LCtrl hold (macros.dtsi)
#define TU_LM &t_lm_alt        // T_LM_LAYER + LAlt  hold (macros.dtsi)
#define TU_RM &mo T_RM_LAYER   // T_RM_LAYER のみ
#define TU_RR &mo T_RR_LAYER   // T_RR_LAYER のみ

// トラックボールでスクロールするための input-processors 共通設定。
//   - zip_xy_scaler 3 64                     : 感度を 1/3 にしてスクロールを遅くする
//   - zip_xy_to_scroll_mapper                 : カーソル移動でなくスクロール出力にする
//   - zip_scroll_transform Y_INVERT           : ボール上方向 = ビュー上方向 (top of trackball = view up)
#define TRACKBALL_SCROLL_PROCESSORS \
      <&zip_xy_scaler 3 64>, \
      <&zip_xy_to_scroll_mapper>, \
      <&zip_scroll_transform INPUT_TRANSFORM_Y_INVERT>

// --------------------------------------------------------------------
// keymap 構造マクロ (bindings = < > 内で使う。keymap-drawer も preprocess 展開)
// --------------------------------------------------------------------

// 1 row 12 キーすべて &none (arrow レイヤーの上 3 段など)
#define ROW_NONE \
  &none &none &none &none &none &none   &none &none &none &none &none &none

// 親指 2 段: 上段 = 全 &none / 下段 = TD_* (sub-layer 共通)
#define THUMB_TD \
  &none &none &none   &none &none &none \
  TD_LL TD_LM &none   &none TD_RM TD_RR

// 親指 2 段すべて &none (T_*_LAYER 共通)
#define THUMB_NONE \
  &none &none &none   &none &none &none \
  &none &none &none   &none &none &none

// row4 (5+5) すべて &none
#define ROW4_NONE \
  &none &none &none &none &none   &none &none &none &none &none

// sub-layer 共通 footer: row4 全 &none + THUMB_TD (NUMBER/SYMBOL*/FUNCTION)
#define FOOTER_TD   ROW4_NONE THUMB_TD
// T_*_LAYER 共通 footer: row4 全 &none + 親指全 &none
#define FOOTER_NONE ROW4_NONE THUMB_NONE

// --------------------------------------------------------------------
// behavior 生成マクロ
// --------------------------------------------------------------------

// シンプルな hold-tap (flavor=hold-preferred / tapping-term-ms=200ms / hold=&kp)。
// name        : 生成する behavior 名
// tap_binding : tap 時の binding (&kp / &kana / &eiji 等)
#define HOLD_TAP_HP200(name, tap_binding) \
    name: name { \
      compatible = "zmk,behavior-hold-tap"; \
      #binding-cells = <2>; \
      tapping-term-ms = <200>; \
      flavor = "hold-preferred"; \
      bindings = <&kp>, <tap_binding>; \
    };

// 矢印 mod-morph + 対応 hold-tap の 1 ペアを生成。
// name : ベース名 (例: ar_up → ar_up と ar_up_ht を生成)
// LAYER, KEY : tap 時に潜るレイヤーと出力キー
// P1, P2     : hold-trigger-key-positions に追加する 2 つの矢印キー位置
//
// mod-morph の分岐 (Ctrl/Alt ローリングタップ救済):
//   - 修飾子なし / Shift / Cmd 押下 → name##_ht (hold-tap)。
//     tap=矢印 / hold=矢印サブレイヤー (HOME/END/PgUp/PgDn)。Shift+HOME 等の
//     範囲選択を維持するため Shift/Cmd ではサブレイヤーを残す。
//   - Ctrl / Alt 押下 → &kp KEY を即時送出 (keep-mods で Ctrl/Alt を保持)。
//     hold-tap は tap を「キーのリリース時」に送るため、ctrl↓ left↓ ctrl↑
//     left↑ のロールでは矢印送出時に既に ctrl が離れ Left 単独になる。
//     即時 &kp で押下時点に送ることで Ctrl+矢印 が成立する。
#define ARROW_BEHAVIOR(name, LAYER, KEY, P1, P2) \
    name##_ht: name##_ht { \
      compatible = "zmk,behavior-hold-tap"; \
      #binding-cells = <2>; \
      flavor = "tap-unless-interrupted"; \
      tapping-term-ms = <800>; \
      hold-while-undecided; \
      hold-while-undecided-linger; \
      bindings = <&mo>, <&kp>; \
      hold-trigger-key-positions = <KEY_POSITION_LEFT_SIDE KEY_POSITION_L_THUMB P1 P2>; \
    }; \
    name: name { \
      compatible = "zmk,behavior-mod-morph"; \
      #binding-cells = <0>; \
      bindings = <&name##_ht LAYER KEY>, <&kp KEY>; \
      mods = <(MOD_LCTL|MOD_LALT)>; \
      keep-mods = <(MOD_LCTL|MOD_LALT)>; \
    };

// al_a 〜 al_z 系 letter mod-morph を生成。
// Shift 未押下 → 素のキー / Shift 押下 → eiji_macro 経由で英語入力モードへ切替えてから大文字出力。
// name   : 生成する behavior 名 (例: al_a)
// letter : 出力キー (例: A)
#define LETTER_MORPH(name, letter) \
    name: name { \
      compatible = "zmk,behavior-mod-morph"; \
      #binding-cells = <0>; \
      bindings = <&kp letter>, <&eiji_macro letter>; \
      mods = <(MOD_LSFT)>; \
      keep-mods = <(MOD_LSFT)>; \
    };

// EIJI 切替 → 指定キー press → pause → release (long-press でリピート可能)。
// name : 生成する behavior 名 (例: en_0 / en_under)
// key  : 出力キー (例: N0 / UNDERSCORE)
// 注: keymap-drawer 上の表示は keymap_drawer.config.yaml の raw_binding_map で設定する。
#define EN_MACRO(name, key) \
    name: name { \
      compatible = "zmk,behavior-macro"; \
      #binding-cells = <0>; \
      bindings = <&macro_tap &kp EIJI>, <&macro_press &kp key>, <&macro_pause_for_release>, <&macro_release &kp key>; \
    };

// 親指上段 (TU) 用 behavior 生成。
//
// TU_MOD : LAYER 起動 + MOD を同時 hold する macro (TU_LL/TU_LM 実体)。
//   name : 生成名 / LAYER : 潜るレイヤー / MOD : hold する修飾子
#define TU_MOD(name, LAYER, MOD) \
    name: name { \
      compatible = "zmk,behavior-macro"; \
      #binding-cells = <0>; \
      bindings = <&macro_press &mo LAYER>, <&macro_press &kp MOD>, <&macro_pause_for_release>, <&macro_release &kp MOD>, <&macro_release &mo LAYER>; \
    };
