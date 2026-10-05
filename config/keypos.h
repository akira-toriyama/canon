#pragma once

// Indices into the matrix transform that imprint.keymap chooses, so another
// transform can renumber them.
#define KEY_POSITION_LL 52
#define KEY_POSITION_LM 53
#define KEY_POSITION_RM 56
#define KEY_POSITION_RR 57
#define KEY_POSITION_LEFT_ARROW 41
#define KEY_POSITION_DOWN_ARROW 42
#define KEY_POSITION_RIGHT_ARROW 43
#define KEY_POSITION_LEFT_SIDE \
   0  1  2  3  4  5 \
  12 13 14 15 16 17 \
  24 25 26 27 28 29 \
  36 37 38 39 40 \
  46 47 48 \
  52 53 54
#define KEY_POSITION_L_THUMB KEY_POSITION_LL KEY_POSITION_LM
