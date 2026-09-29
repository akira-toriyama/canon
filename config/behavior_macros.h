#pragma once

// Binding aliases and behavior-generating macros of imprint.keymap, which
// includes this header; keymap-drawer's preprocess expands them as well.

#include "layers.h"
#include "keypos.h"

// macOS input source keys.
#define EIJI LANGUAGE_2
#define KANA LANGUAGE_1

// Lower thumb row (TD = thumb down): mod-taps, hold = modifier, tap = key.
#define TD_LL &mt LEFT_SHIFT RETURN
#define TD_LM &mt LEFT_COMMAND BACKSPACE
#define TD_RM &mt LEFT_ALT ESCAPE
#define TD_RR &mt LEFT_CONTROL SPACE

// Momentary layer keys in the left half of the base layer's row 4.
// NAME: SYMBOL1 / SYMBOL2 / NUMBER / FUNCTION
#define MO_LAYER(NAME) &mo NAME##_LAYER

// Upper thumb row (TU = thumb up): layer keys; LL and LM also hold a modifier.
#define TU_LL &t_ll_ctrl       // T_LL_LAYER + LCtrl held (macros.dtsi)
#define TU_LM &t_lm_alt        // T_LM_LAYER + LAlt held (macros.dtsi)
#define TU_RM &mo T_RM_LAYER
#define TU_RR &mo T_RR_LAYER

// Input processors of the left trackball, which always scrolls:
//   zip_xy_scaler 3 64: motion times 3/64, for slow scrolling
//   zip_xy_to_scroll_mapper: scroll instead of moving the pointer
//   zip_scroll_transform Y_INVERT: rolling the ball up scrolls the view up
#define TRACKBALL_SCROLL_PROCESSORS \
      <&zip_xy_scaler 3 64>, \
      <&zip_xy_to_scroll_mapper>, \
      <&zip_scroll_transform INPUT_TRANSFORM_Y_INVERT>

// Rows of &none for the layers' bindings = < >.
#define ROW_NONE \
  &none &none &none &none &none &none   &none &none &none &none &none &none

// Both thumb rows of the sub-layers: the upper row empty, the lower row the
// TD_* mod-taps.
#define THUMB_TD \
  &none &none &none   &none &none &none \
  TD_LL TD_LM &none   &none TD_RM TD_RR

#define THUMB_NONE \
  &none &none &none   &none &none &none \
  &none &none &none   &none &none &none

// Row 4, 5 keys per half.
#define ROW4_NONE \
  &none &none &none &none &none   &none &none &none &none &none

// NUMBER / SYMBOL* / FUNCTION layers.
#define FOOTER_TD   ROW4_NONE THUMB_TD
// T_*_LAYER.
#define FOOTER_NONE ROW4_NONE THUMB_NONE

// hold-tap, hold-preferred, 200 ms: hold = &kp, tap = tap_binding (&kana, ...).
#define HOLD_TAP_HP200(name, tap_binding) \
    name: name { \
      compatible = "zmk,behavior-hold-tap"; \
      #binding-cells = <2>; \
      tapping-term-ms = <200>; \
      flavor = "hold-preferred"; \
      bindings = <&kp>, <tap_binding>; \
    };

// An arrow key: the mod-morph `name` over the hold-tap `name##_ht`.
//   LAYER, KEY: the sub-layer the hold enters and the arrow the tap sends
//   P1, P2: two other arrow keys, added to hold-trigger-key-positions
// With no modifier, Shift or Cmd it is the hold-tap: tap = the arrow, hold =
// the sub-layer (LArr / RArr / UArr / DArr: Home / End / PgUp / PgDn), kept
// under Shift and Cmd so that Shift+Home and the like select. With Ctrl or Alt
// held it sends &kp KEY at the press (keep-mods keeps Ctrl / Alt): a hold-tap
// sends its tap at the release, so in the roll ctrl down, left down, ctrl up,
// left up the arrow would go out after Ctrl was released, as a bare Left.
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

// A letter key (al_a .. al_z): the letter, or with Shift eiji_macro (EIJI,
// then the letter), so that Shift+letter types a Latin capital in any input
// mode.
#define LETTER_MORPH(name, letter) \
    name: name { \
      compatible = "zmk,behavior-mod-morph"; \
      #binding-cells = <0>; \
      bindings = <&kp letter>, <&eiji_macro letter>; \
      mods = <(MOD_LSFT)>; \
      keep-mods = <(MOD_LSFT)>; \
    };

// EIJI, then key held until the release, so that it repeats (en_0,
// en_under, ...). keymap-drawer labels them through raw_binding_map in
// keymap_drawer.config.yaml, generated from eiji_macros.dtsi.
#define EN_MACRO(name, key) \
    name: name { \
      compatible = "zmk,behavior-macro"; \
      #binding-cells = <0>; \
      bindings = <&macro_tap &kp EIJI>, <&macro_press &kp key>, <&macro_pause_for_release>, <&macro_release &kp key>; \
    };

// Upper thumb key that holds LAYER and MOD together (TU_LL, TU_LM).
#define TU_MOD(name, LAYER, MOD) \
    name: name { \
      compatible = "zmk,behavior-macro"; \
      #binding-cells = <0>; \
      bindings = <&macro_press &mo LAYER>, <&macro_press &kp MOD>, <&macro_pause_for_release>, <&macro_release &kp MOD>, <&macro_release &mo LAYER>; \
    };
