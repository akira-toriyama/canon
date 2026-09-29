#!/usr/bin/env bash
#
# Build canon's firmware in Docker and copy the images to ./firmware/.
#
#   ./scripts/build-zmk.sh                   # every target in build.yaml (= all)
#   ./scripts/build-zmk.sh imprint           # the imprint group: build.yaml's imprint* shields
#   ./scripts/build-zmk.sh imprint_left      # one shield; its board comes from build.yaml
#   ./scripts/build-zmk.sh <board>:<shield>  # a pair that build.yaml does not list
#   ./scripts/build-zmk.sh imprint_dongle --logging
#   ./scripts/build-zmk.sh imprint --reset
#   ./scripts/build-zmk.sh prospector --sprite assets/<name>.gif
#   ./scripts/build-zmk.sh prospector --beacon ../zmk-beacon
#   ./scripts/build-zmk.sh prospector --kconfig CONFIG_LV_USE_SYSMON=y \
#     --kconfig CONFIG_LV_USE_PERF_MONITOR=y --tag perf
#   ./scripts/build-zmk.sh --update          # west update first
#   ./scripts/build-zmk.sh --clean           # delete the workspace and exit
#
# Options (local builds only: CI and releases build the plain images):
#   --logging         USB CDC logging: CONFIG_ZMK_USB_LOGGING=y, a 4 KiB CDC ring
#                     buffer (the 1 KiB default drops the boot log before the host
#                     opens the port) and ZMK at INFO level
#                     (CONFIG_ZMK_LOGGING_MINIMAL=y: at DEBUG the Imprint Dongle's
#                     boot overflows the 8 KiB log buffer before the log thread
#                     starts, and DEBUG lines carry keycodes). ZMK's split
#                     battery and connection lines are DEBUG only: for them add
#                     --kconfig CONFIG_ZMK_LOGGING_MINIMAL=n.
#   --reset           CONFIG_ZMK_SETTINGS_RESET_ON_START=y on the real shield: the
#                     image erases the settings, BLE bonds included, at every
#                     boot. Flash it with flash-reset.sh, then the normal image.
#   --sprite <gif>    zmk-beacon's animated sprite (CONFIG_BEACON_SPRITE_GIF) in
#                     the prospector target only, named under the HP bar after
#                     the GIF's file name (assets/sprite-name.sh). Sprite GIFs are
#                     personal files: never committed, never in CI or a release,
#                     and this script prints neither the GIF's path nor the name.
#   --beacon <dir>    build against the zmk-beacon checkout <dir>, its working
#                     tree as it is, instead of the revision config/west.yml pins.
#                     The images carry -beacon.
#   --kconfig CONFIG_NAME=VALUE
#                     one more Kconfig line for every target, merged after
#                     config/<shield>.conf and the sprite and logging lines.
#                     Repeatable; the images carry -kconfig. CONFIG_BEACON_SPRITE_*
#                     go only through --sprite, and nothing that turns the
#                     display off combines with --sprite.
#   --tag <name>      appended to the build directory and the image name.
#   --update          west update before building: moves zmk@main, the
#                     zmk-keyboards branch and every module to the manifest.
#   --clean           delete the workspace and exit.
# --reset combines with neither --logging nor --sprite.
#
# Images: firmware/<shield>[-sprite][-logging][-kconfig][-beacon][_RESET][-<tag>].uf2
# (git-ignored), copied once every target of the run has built. A bare
# <shield>.uf2 or <shield>_RESET.uf2, which flash-watch.sh, flash-reset.sh and
# `flash-dongle.sh <device>` take, is therefore always a pinned build. The run ends with one line
# per image (sha256, FLASH and RAM use) and the revisions it built from.
#
# Workspace: $ZMK_WS/cfgrepo is the west topdir (manifest config/west.yml). West's
# clones (zmk/, zephyr/, modules/, ...) and build/<name>/ (build.log included)
# stay between runs; each run syncs config/, patches/, scripts/ and build.yaml
# into it and clears the per-run inputs .sprite/, .kconfig/ and .beacon/.
# west update runs on the first build, when zmk/app is missing, or with
# --update. Every build without --beacon first checks out modules/zmk-beacon
# at its pin (that project only), so a pin bump needs no --update. The steps
# inside the container are scripts/zmk-west.sh, which CI runs too.
#
# Environment: ZMK_WS (default ~/.cache/zmk-canon), ZMK_IMAGE (default
# zmkfirmware/zmk-build-arm:stable).
set -euo pipefail

# Relative --sprite and --beacon paths are the caller's.
CALLER_DIR="$PWD"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

WS="${ZMK_WS:-$HOME/.cache/zmk-canon}"
IMAGE="${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
CFG="$WS/cfgrepo"
FORCE_UPDATE=0
LOGGING=0
RESET=0
SPRITE=""
SPRITE_NAME=""
BEACON=""
BEACON_REV=""
TAG=""
KCONFIG=()
ARGS=()

# The ZMK defaults under CONFIG_ZMK_USB_LOGGING are a 1 KiB CDC ring and ZMK at
# DEBUG (zmk app/Kconfig). 4096 holds the Prospector Dongle's boot (about 1.3
# KB) and the Imprint Dongle's INFO boot (about 3 KB) until the port opens;
# the ring is allocated twice (RX and TX, Zephyr cdc_acm.c).
LOGGING_CONF=(
  CONFIG_ZMK_USB_LOGGING=y
  CONFIG_USB_CDC_ACM_RINGBUF_SIZE=4096
  CONFIG_ZMK_LOGGING_MINIMAL=y
)

die() {
  local rc=$1
  shift
  echo "build-zmk.sh: $*" >&2
  exit "$rc"
}

while [ $# -gt 0 ]; do
  arg="$1"
  shift
  case "$arg" in
    --clean)
      echo "removing the workspace $WS"
      rm -rf "$WS"
      exit 0
      ;;
    --update) FORCE_UPDATE=1 ;;
    --logging) LOGGING=1 ;;
    --reset) RESET=1 ;;
    --sprite | --beacon | --kconfig | --tag)
      if [ $# -eq 0 ] || [ -z "$1" ]; then die 2 "$arg needs a value"; fi
      case "$arg" in
        --sprite) SPRITE="$1" ;;
        --beacon) BEACON="$1" ;;
        --kconfig) KCONFIG+=("$1") ;;
        --tag) TAG="$1" ;;
      esac
      shift
      ;;
    -h | --help)
      awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) die 2 "unknown option $arg (see --help)" ;;
    *) ARGS+=("$arg") ;;
  esac
done

# A reset image only erases the settings: logging adds nothing to it, and the
# prospector has no settings to reset (zmk-beacon: CONFIG_ZMK_BLE=n).
if [ "$RESET" -eq 1 ] && [ "$LOGGING" -eq 1 ]; then
  die 2 "--reset and --logging do not combine"
fi
if [ "$RESET" -eq 1 ] && [ -n "$SPRITE" ]; then
  die 2 "--reset and --sprite do not combine"
fi
if [ -n "$SPRITE" ]; then
  case "$SPRITE" in /*) ;; *) SPRITE="$CALLER_DIR/$SPRITE" ;; esac
  # Never the path in a message: a GIF's file name names its subject.
  if [ ! -f "$SPRITE" ] || [ ! -r "$SPRITE" ]; then die 2 "--sprite: no readable GIF at that path"; fi
  SPRITE_NAME="$("$REPO/assets/sprite-name.sh" "$SPRITE")"
fi
if [ -n "$BEACON" ]; then
  case "$BEACON" in /*) ;; *) BEACON="$CALLER_DIR/$BEACON" ;; esac
  [ -d "$BEACON" ] || die 2 "--beacon: $BEACON is not a directory"
  BEACON="$(cd "$BEACON" && pwd)"
  if ! grep -Eq '^name:[[:space:]]*zmk-beacon[[:space:]]*$' "$BEACON/zephyr/module.yml" 2>/dev/null; then
    die 2 "--beacon: $BEACON/zephyr/module.yml does not declare name: zmk-beacon"
  fi
  BEACON_REV="$(git -C "$BEACON" describe --always --dirty 2>/dev/null || echo 'no git revision')"
  # Kconfig quotes the value it was given for an undefined symbol, and the
  # sprite's name is private: a zmk-beacon before 0a64fc9 (or one that renamed
  # the symbol) would print it on the way to failing.
  if [ -n "$SPRITE" ] && ! grep -Eq '^[[:space:]]*config[[:space:]]+BEACON_SPRITE_NAME[[:space:]]*$' "$BEACON/Kconfig" 2>/dev/null; then
    die 2 "--beacon: $BEACON/Kconfig defines no BEACON_SPRITE_NAME, so Kconfig would print the sprite's name; build this checkout without --sprite"
  fi
fi
for kv in ${KCONFIG[@]+"${KCONFIG[@]}"}; do
  case "$kv" in
    *$'\n'*) die 2 "--kconfig takes one line" ;;
    CONFIG_BEACON_SPRITE_*) die 2 "--kconfig: CONFIG_BEACON_SPRITE_* go only through --sprite" ;;
    CONFIG_ZMK_DISPLAY=* | CONFIG_ZMK_DISPLAY_*)
      # The sprite needs the custom status screen; Kconfig would print the
      # name it could then not take.
      if [ -n "$SPRITE" ]; then die 2 "--kconfig: ${kv%%=*} does not combine with --sprite"; fi
      ;;
    CONFIG_?*=?*) ;;
    *) die 2 "--kconfig takes CONFIG_NAME=VALUE, not $kv" ;;
  esac
  case "${kv%%=*}" in *[!A-Za-z0-9_]*) die 2 "--kconfig: not a Kconfig symbol: ${kv%%=*}" ;; esac
done
case "$TAG" in *[!A-Za-z0-9._-]*) die 2 "--tag takes letters, digits, '.', '_' and '-'" ;; esac

# Targets as board<TAB>shield. The groups come from build.yaml's shield names,
# never from a list here: all = every target, imprint = the imprint* shields.
PAIRS="$("$REPO/scripts/zmk-west.sh" pairs)"
TARGETS=()
[ ${#ARGS[@]} -gt 0 ] || ARGS=(all)
for arg in "${ARGS[@]}"; do
  case "$arg" in
    all | imprint)
      filter='.'
      if [ "$arg" = imprint ]; then filter='^imprint'; fi
      rows="$(printf '%s\n' "$PAIRS" | awk -F'\t' -v p="$filter" '$2 ~ p')"
      [ -n "$rows" ] || die 1 "group $arg matches no shield in build.yaml"
      while IFS= read -r row; do TARGETS+=("$row"); done <<<"$rows"
      ;;
    *:*)
      case "$arg" in :* | *:) die 2 "pass <board>:<shield> with both parts, not $arg" ;; esac
      TARGETS+=("${arg%%:*}	${arg##*:}")
      ;;
    *)
      board="$(printf '%s\n' "$PAIRS" | awk -F'\t' -v s="$arg" '$2 == s { print $1; exit }')"
      [ -n "$board" ] || die 1 "shield $arg is not in build.yaml (pass <board>:<shield> to build it anyway)"
      TARGETS+=("$board	$arg")
      ;;
  esac
done
if [ -n "$SPRITE" ]; then
  has_prospector=0
  for row in "${TARGETS[@]}"; do
    if [ "${row##*	}" = prospector ]; then has_prospector=1; fi
  done
  [ "$has_prospector" -eq 1 ] || die 2 "--sprite applies to prospector only, which this run does not build"
fi

# For the target in row ("board<TAB>shield"), sets BOARD, SHIELD, NAME
# (<shield><suffix>: the build directory and the image name), SUFFIX and
# CMAKE_ARGS. Kconfig fragments merge in list order after config/<shield>.conf,
# and -DCONFIG_* after every fragment: --logging is a fragment so that
# --kconfig can still override it.
plan() {
  local conf=()
  BOARD="${1%%	*}"
  SHIELD="${1##*	}"
  SUFFIX=""
  CMAKE_ARGS=()
  if [ -n "$SPRITE" ] && [ "$SHIELD" = prospector ]; then
    conf+=(/workspace/.sprite/sprite.conf)
    SUFFIX="$SUFFIX-sprite"
  fi
  if [ "$LOGGING" -eq 1 ]; then
    conf+=(/workspace/.kconfig/logging.conf)
    SUFFIX="$SUFFIX-logging"
  fi
  if [ ${#KCONFIG[@]} -gt 0 ]; then
    conf+=(/workspace/.kconfig/extra.conf)
    SUFFIX="$SUFFIX-kconfig"
  fi
  if [ ${#conf[@]} -gt 0 ]; then
    CMAKE_ARGS+=("-DEXTRA_CONF_FILE=$(IFS=';' && echo "${conf[*]}")")
  fi
  # Zephyr keys modules by the name in zephyr/module.yml and takes extra
  # modules after west's projects (zephyr_module.py parse_modules), so this
  # one replaces modules/zmk-beacon.
  if [ -n "$BEACON" ]; then
    CMAKE_ARGS+=(-DZMK_EXTRA_MODULES=/workspace/.beacon)
    SUFFIX="$SUFFIX-beacon"
  fi
  if [ "$RESET" -eq 1 ]; then
    CMAKE_ARGS+=(-DCONFIG_ZMK_SETTINGS_RESET_ON_START=y)
    SUFFIX="${SUFFIX}_RESET"
  fi
  if [ -n "$TAG" ]; then SUFFIX="$SUFFIX-$TAG"; fi
  NAME="$SHIELD$SUFFIX"
}

if ! docker info >/dev/null 2>&1; then
  die 1 "the Docker daemon is not running (open -a Docker)"
fi

# Only the build's inputs: west's clones and build/ share this topdir. --delete
# drops a file removed from the repository, which the build would still read.
mkdir -p "$CFG"
rsync -a --delete "$REPO/config" "$REPO/patches" "$REPO/scripts" "$REPO/build.yaml" "$CFG/"
# The per-run inputs, written below only for the options of this run.
rm -rf "$CFG/.sprite" "$CFG/.kconfig" "$CFG/.beacon"

# The container sees only the workspace, so the GIF is copied in under a fixed
# name. Its path and name reach the build in a Kconfig fragment
# (EXTRA_CONF_FILE), never as -DCONFIG_...: west prints the whole cmake
# command line when the configure step fails, and both name the subject.
# Kconfig strings keep their quotes.
if [ -n "$SPRITE" ]; then
  mkdir -p "$CFG/.sprite"
  cp "$SPRITE" "$CFG/.sprite/sprite.gif" 2>/dev/null || die 1 "--sprite: cannot copy the GIF into the workspace"
  {
    echo 'CONFIG_BEACON_SPRITE_GIF="/workspace/.sprite/sprite.gif"'
    echo "CONFIG_BEACON_SPRITE_NAME=\"$SPRITE_NAME\""
  } >"$CFG/.sprite/sprite.conf"
fi
if [ "$LOGGING" -eq 1 ]; then
  mkdir -p "$CFG/.kconfig"
  printf '%s\n' "${LOGGING_CONF[@]}" >"$CFG/.kconfig/logging.conf"
fi
if [ ${#KCONFIG[@]} -gt 0 ]; then
  mkdir -p "$CFG/.kconfig"
  printf '%s\n' "${KCONFIG[@]}" >"$CFG/.kconfig/extra.conf"
fi
# Without the checkout's git data, Claude Code state and built images.
if [ -n "$BEACON" ]; then
  mkdir -p "$CFG/.beacon"
  rsync -a --exclude '/.git' --exclude '/.claude/' --exclude '/firmware/' "$BEACON/" "$CFG/.beacon/"
fi

NEED_UPDATE=0
if [ ! -d "$CFG/.west" ] || [ ! -d "$CFG/zmk/app" ] || [ "$FORCE_UPDATE" -eq 1 ]; then
  NEED_UPDATE=1
fi

echo "=========================================="
echo " workspace   : $CFG"
echo " image       : $IMAGE"
echo " west update : $([ "$NEED_UPDATE" -eq 1 ] && echo yes || echo 'no (cached; --update forces it)')"
if [ -n "$BEACON" ]; then
  echo " zmk-beacon  : $BEACON @ $BEACON_REV (--beacon, overrides the pin in config/west.yml)"
else
  echo " zmk-beacon  : the revision config/west.yml pins"
fi
if [ "$LOGGING" -eq 1 ]; then echo " logging     : ${LOGGING_CONF[*]}"; fi
if [ "$RESET" -eq 1 ]; then echo " reset       : CONFIG_ZMK_SETTINGS_RESET_ON_START=y"; fi
if [ -n "$SPRITE" ]; then
  echo " sprite      : a $(wc -c <"$SPRITE" | tr -d ' ') byte GIF, a name of ${#SPRITE_NAME} characters (prospector only; neither printed)"
fi
if [ ${#KCONFIG[@]} -gt 0 ]; then echo " kconfig     : ${KCONFIG[*]}"; fi
echo " targets     :"
for row in "${TARGETS[@]}"; do
  plan "$row"
  echo "   $BOARD / $SHIELD -> firmware/$NAME.uf2"
done
echo "=========================================="

# One container per step; scripts/zmk-west.sh sets each one up.
in_container() {
  docker run --rm -v "$CFG:/workspace" -w /workspace -e ZEPHYR_BASE=/workspace/zephyr \
    "$IMAGE" scripts/zmk-west.sh "$@"
}

if [ "$NEED_UPDATE" -eq 1 ]; then in_container update; fi
if [ -z "$BEACON" ]; then in_container pin zmk-beacon; fi
in_container patch
for row in "${TARGETS[@]}"; do
  plan "$row"
  in_container build "$BOARD" "$SHIELD" "$SUFFIX" ${CMAKE_ARGS[@]+"${CMAKE_ARGS[@]}"}
done

mkdir -p "$REPO/firmware"
for row in "${TARGETS[@]}"; do
  plan "$row"
  cp "$CFG/build/$NAME/zephyr/zmk.uf2" "$REPO/firmware/$NAME.uf2"
done

# FLASH and RAM from the linker's memory table in build.log; left out rather
# than failing the run when the table is missing.
echo
echo "images:"
for row in "${TARGETS[@]}"; do
  plan "$row"
  sha="$(shasum -a 256 "$REPO/firmware/$NAME.uf2" | cut -c1-12)"
  mem="$(awk '
    $1 == "FLASH:" { f = "FLASH " $2 " " $3 " / " $4 " " $5 " " $6 }
    $1 == "RAM:"   { r = "RAM " $2 " " $3 " / " $4 " " $5 " " $6 }
    END { print f (f != "" && r != "" ? "  " : "") r }
  ' "$CFG/build/$NAME/build.log" 2>/dev/null || true)"
  echo "  firmware/$NAME.uf2  $sha  $mem"
done
zmk_rev="$(git -C "$CFG/zmk" log -1 --format='%h %cs' 2>/dev/null || true)"
keyboards_rev="$(git -C "$CFG/zmk-keyboards" log -1 --format='%h' 2>/dev/null || true)"
if [ -n "$BEACON" ]; then
  beacon_rev="$BEACON @ $BEACON_REV (--beacon)"
else
  beacon_rev="$(git -C "$CFG/modules/zmk-beacon" log -1 --format='%h' 2>/dev/null || true)"
  beacon_rev="${beacon_rev:-?} (pin)"
fi
echo "revisions: zmk ${zmk_rev:-?}, zmk-keyboards ${keyboards_rev:-?}, zmk-beacon $beacon_rev"
