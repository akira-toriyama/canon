#!/usr/bin/env bash
#
# The name the Prospector Dongle shows under its HP bar for a sprite GIF,
# from the GIF's file name: the extension dropped, whitespace trimmed at both
# ends, the first letter upper-cased ("my sprite.gif" -> "My sprite"; the
# user's rule, projects t-er81, 2026-09-29). scripts/build-zmk.sh --sprite
# passes the result to zmk-beacon as CONFIG_BEACON_SPRITE_NAME. Printable ASCII
# on one line, without a double quote, a backslash or "??": the HP bar's font
# has no other glyphs, Kconfig would need escaping, and "??x" is a C trigraph
# in autoconf.h, so anything else is an error and a build never shows a wrong
# name. Committed, like assets/README.md, next to the git-ignored personal
# files (the two exceptions in .gitignore); it prints the name, which names the
# subject, so never paste its output into a commit, a PR or a doc; its error
# messages name neither the file nor the name for the same reason.
#
#   assets/sprite-name.sh <gif>    # prints the name
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 <gif>" >&2
  exit 2
fi

name="$(basename -- "$1")"
name="${name%.*}"
name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ -z "$name" ]; then
  echo "sprite-name: the GIF's file name leaves no name" >&2
  exit 2
fi
# grep reads lines, so a newline is checked apart; a name of semicolons only
# would collapse to an empty CMake list and the build's sprite box would
# disagree with the screen's.
case "$name" in
  *$'\n'*) echo "sprite-name: the GIF's file name must be one line" >&2; exit 2 ;;
  *[!\;]*) ;;
  *) echo "sprite-name: the GIF's file name needs a character other than ';'" >&2; exit 2 ;;
esac
if printf '%s' "$name" | LC_ALL=C grep -Eq '[^ -~]|["\\]|\?\?'; then
  echo "sprite-name: the GIF's file name must be printable ASCII without a double quote, a backslash or \"??\"" >&2
  exit 2
fi
# bash 3.2 (macOS) has no ${name^}.
first="$(printf '%s' "$name" | cut -c1 | tr '[:lower:]' '[:upper:]')"
printf '%s\n' "${first}${name#?}"
