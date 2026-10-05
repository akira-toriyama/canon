#pragma once

// Binding aliases and behavior-generating macros of imprint.keymap, which
// includes this header; keymap-drawer's preprocess expands them as well.

#include "layers.h"
#include "keypos.h"

// macOS input source keys.
#define EIJI LANGUAGE_2
#define KANA LANGUAGE_1

// Lower thumb row (TD = thumb down).
#define TD_LL &mt LEFT_SHIFT RETURN
#define TD_LM &mt LEFT_COMMAND BACKSPACE
#define TD_RM &mt LEFT_ALT ESCAPE
#define TD_RR &mt LEFT_CONTROL SPACE

#define MO_LAYER(NAME) &mo NAME##_LAYER

// Upper thumb row (TU = thumb up). TU_LL / TU_LM hold Ctrl / Alt with their
// layer, so that the thumb doubles as the modifier of a mouse click.
#define TU_LL &t_ll_ctrl
#define TU_LM &t_lm_alt
#define TU_RM &mo T_RM_LAYER
#define TU_RR &mo T_RR_LAYER

// The scaler slows the scrolling; Y_INVERT makes rolling the ball up scroll
// the view up.
#define TRACKBALL_SCROLL_PROCESSORS \
      <&zip_xy_scaler 3 64>, \
      <&zip_xy_to_scroll_mapper>, \
      <&zip_scroll_transform INPUT_TRANSFORM_Y_INVERT>

#define ROW_NONE \
  &none &none &none &none &none &none   &none &none &none &none &none &none

#define THUMB_TD \
  &none &none &none   &none &none &none \
  TD_LL TD_LM &none   &none TD_RM TD_RR

#define THUMB_NONE \
  &none &none &none   &none &none &none \
  &none &none &none   &none &none &none

// Row 4, 5 keys per half.
#define ROW4_NONE \
  &none &none &none &none &none   &none &none &none &none &none

#define FOOTER_TD   ROW4_NONE THUMB_TD
#define FOOTER_NONE ROW4_NONE THUMB_NONE

#define HOLD_TAP_HP200(name, tap_binding) \
    name: name { \
      compatible = "zmk,behavior-hold-tap"; \
      #binding-cells = <2>; \
      tapping-term-ms = <200>; \
      flavor = "hold-preferred"; \
      bindings = <&kp>, <tap_binding>; \
    };

// An arrow key. P1, P2: other arrow keys whose press within the tapping term
// decides the hold-tap as a hold. Shift and Cmd keep the hold-tap, so that
// Shift+Home and the like select. With Ctrl or Alt held the mod-morph sends
// &kp KEY at the press, keeping Ctrl / Alt (keep-mods): a hold-tap sends its
// tap at the release, so in the roll ctrl down, left down, ctrl up, left up
// the arrow would go out after Ctrl was released, as a bare Left.
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

// Shift+letter goes through eiji_macro, EIJI first, so that it types a Latin
// capital in any input mode.
#define LETTER_MORPH(name, letter) \
    name: name { \
      compatible = "zmk,behavior-mod-morph"; \
      #binding-cells = <0>; \
      bindings = <&kp letter>, <&eiji_macro letter>; \
      mods = <(MOD_LSFT)>; \
      keep-mods = <(MOD_LSFT)>; \
    };

// EIJI first, so that the character comes out as ASCII in any input mode; the
// key then stays down until the release, so that it repeats. Instances go in
// eiji_macros.dtsi, the source of their keymap-drawer labels.
#define EN_MACRO(name, key) \
    name: name { \
      compatible = "zmk,behavior-macro"; \
      #binding-cells = <0>; \
      bindings = <&macro_tap &kp EIJI>, <&macro_press &kp key>, <&macro_pause_for_release>, <&macro_release &kp key>; \
    };

// Holds LAYER and MOD, and releases MOD before LAYER: the vkey behavior
// (patches/zmk/vkey-report.patch) masks a held Ctrl / Alt from a vkey's press
// until a layer turns off, so the other order would unmask MOD while it is
// still down and send the host an extra Ctrl / Alt tap.
#define TU_MOD(name, LAYER, MOD) \
    name: name { \
      compatible = "zmk,behavior-macro"; \
      #binding-cells = <0>; \
      bindings = <&macro_press &mo LAYER>, <&macro_press &kp MOD>, <&macro_pause_for_release>, <&macro_release &kp MOD>, <&macro_release &mo LAYER>; \
    };
