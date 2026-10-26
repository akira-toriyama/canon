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
#   ./scripts/build-zmk.sh prospector --sprite /Volumes/HDD/assets/canon/prospector/sprites/<name>.gif
#   ./scripts/build-zmk.sh prospector --module ../zmk-beacon
#   ./scripts/build-zmk.sh imprint --module ../zmk-lantern --module ../zmk-beacon
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
#                     the prospector target only, named above the HP bar after
#                     the sprite sender's name dictionary, else the GIF's file
#                     name (assets/sprite-name.py). Sprite GIFs are
#                     personal files kept off the repository (assets/README.md):
#                     never committed, never in CI or a release, and this script
#                     prints neither the GIF's path nor the name.
#   --module <dir>    build against the Zephyr module checkout <dir>, its working
#                     tree as it is: in place of the revision config/west.yml pins
#                     when an own module has that name (its zephyr/module.yml),
#                     added when the manifest lacks it yet. Repeatable. The
#                     images carry -<name> without a leading zmk- (-beacon,
#                     -lantern), in name order.
#   --kconfig CONFIG_NAME=VALUE
#                     one more Kconfig line for every target, merged after
#                     config/<shield>.conf and the sprite and logging lines.
#                     Repeatable; the images carry -kconfig. CONFIG_BEACON_SPRITE_*
#                     go only through --sprite, and CONFIG_ZMK_DISPLAY and
#                     CONFIG_ZMK_DISPLAY_* lines do not combine with it.
#   --tag <name>      appended to the build directory and the image name.
#   --update          west update before building: moves zmk@main, the
#                     zmk-keyboards branch and every module to the manifest.
#   --clean           delete the workspace and exit.
#   -h, --help        print this header and exit.
# --reset combines with neither --logging nor --sprite.
#
# Images: firmware/<shield>[-sprite][-logging][-kconfig][-<module>...][_RESET][-<tag>].uf2
# (git-ignored), copied once every target of the run has built. A bare
# <shield>.uf2 or <shield>_RESET.uf2, which flash-watch.sh, flash-reset.sh and
# `flash-dongle.sh <device>` take, is therefore always a pinned build. The run ends with one line
# per image (sha256, FLASH and RAM use) and the revisions it built from.
#
# Workspace: $ZMK_WS/cfgrepo is the west topdir (manifest config/west.yml). West's
# clones (zmk/, zephyr/, modules/, ...) and build/<name>/ (build.log included)
# stay between runs; each run syncs config/, patches/, scripts/ and build.yaml
# into it and clears the per-run inputs .sprite/, .kconfig/ and .modules/.
# west update runs on the first build, when zmk/app is missing, or with
# --update. Every build first checks out each own module (the projects
# `stamp.py pins` lists from config/west.yml) at its pin, those projects only,
# so a pin bump needs no --update; one a --module replaces too, since the
# stamp takes the pin's tree id from that clone. The steps inside the
# container are scripts/zmk-west.sh, which CI runs too.
#
# Environment: ZMK_WS (default ~/.cache/zmk-canon), ZMK_IMAGE (default
# zmkfirmware/zmk-build-arm:stable).
set -euo pipefail

# Relative --sprite and --module paths are the caller's.
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
MODULE_DIRS=()
MODULE_NAMES=()
MODULE_REVS=()
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
    --sprite | --module | --kconfig | --tag)
      if [ $# -eq 0 ] || [ -z "$1" ]; then die 2 "$arg needs a value"; fi
      case "$arg" in
        --sprite) SPRITE="$1" ;;
        --module) MODULE_DIRS+=("$1") ;;
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
  SPRITE_NAME="$(python3 "$REPO/assets/sprite-name.py" "$SPRITE")"
fi
# The own modules config/west.yml pins (name, west path, commit): every build
# checks each out at its pin, and a --module of the same name stands in.
pins="$(python3 "$REPO/scripts/stamp.py" pins)" || die 1 "cannot list the own modules of config/west.yml (above)"
OWN_NAMES=()
OWN_PATHS=()
OWN_REVS=()
if [ -n "$pins" ]; then
  while IFS=$'\t' read -r name path rev; do
    OWN_NAMES+=("$name")
    OWN_PATHS+=("$path")
    OWN_REVS+=("$rev")
  done <<<"$pins"
fi

# The index of module NAME in OWN_NAMES or MODULE_NAMES; nothing when absent.
own_index() {
  local i
  for i in ${OWN_NAMES[@]+"${!OWN_NAMES[@]}"}; do
    if [ "${OWN_NAMES[$i]}" = "$1" ]; then echo "$i"; return; fi
  done
}
module_index() {
  local j
  for j in ${MODULE_NAMES[@]+"${!MODULE_NAMES[@]}"}; do
    if [ "${MODULE_NAMES[$j]}" = "$1" ]; then echo "$j"; return; fi
  done
}

# Zephyr keys modules by the name in zephyr/module.yml (zephyr_module.py
# parse_modules): that name decides which pin, if any, the checkout replaces.
for i in ${MODULE_DIRS[@]+"${!MODULE_DIRS[@]}"}; do
  dir="${MODULE_DIRS[$i]}"
  case "$dir" in /*) ;; *) dir="$CALLER_DIR/$dir" ;; esac
  [ -d "$dir" ] || die 2 "--module: $dir is not a directory"
  dir="$(cd "$dir" && pwd)"
  [ -f "$dir/zephyr/module.yml" ] || die 2 "--module: $dir has no zephyr/module.yml, so it is no Zephyr module"
  name="$(sed -nE 's/^name:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$dir/zephyr/module.yml" | head -n 1)"
  [ -n "$name" ] || die 2 "--module: $dir/zephyr/module.yml declares no name:"
  case "$name" in *[!A-Za-z0-9._-]*) die 2 "--module: the module name $name does not fit an image name" ;; esac
  # Its suffix would be the sprite build's, which the stamp drops (scripts/stamp.py).
  [ "${name#zmk-}" != sprite ] || die 2 "--module: the module name $name would give the image the sprite build's suffix"
  [ -z "$(module_index "$name")" ] || die 2 "--module: two checkouts of $name"
  MODULE_DIRS[i]="$dir"
  MODULE_NAMES+=("$name")
  MODULE_REVS+=("$(git -C "$dir" describe --always --dirty 2>/dev/null || echo 'no git revision')")
  # Kconfig quotes the value it was given for an undefined symbol, and the
  # sprite's name is private: a zmk-beacon before 0a64fc9 (or one that renamed
  # the symbol) would print it on the way to failing.
  if [ "$name" = zmk-beacon ] && [ -n "$SPRITE" ] && ! grep -Eq '^[[:space:]]*config[[:space:]]+BEACON_SPRITE_NAME[[:space:]]*$' "$dir/Kconfig" 2>/dev/null; then
    die 2 "--module: $dir/Kconfig defines no BEACON_SPRITE_NAME, so Kconfig would print the sprite's name; build this checkout without --sprite"
  fi
done
# The image suffix and ZMK_EXTRA_MODULES follow name order, not the command
# line's, so that the same checkouts build into the same directory.
MODULES_SORTED=()
if [ ${#MODULE_NAMES[@]} -gt 0 ]; then
  while IFS= read -r name; do MODULES_SORTED+=("$name"); done < <(printf '%s\n' "${MODULE_NAMES[@]}" | LC_ALL=C sort)
fi
for kv in ${KCONFIG[@]+"${KCONFIG[@]}"}; do
  case "$kv" in
    *$'\n'*) die 2 "--kconfig takes one line" ;;
    CONFIG_BEACON_SPRITE_*) die 2 "--kconfig: CONFIG_BEACON_SPRITE_* go only through --sprite" ;;
    CONFIG_ZMK_DISPLAY=* | CONFIG_ZMK_DISPLAY_*)
      # zmk-beacon's BEACON_SPRITE_GIF depends on the custom status screen,
      # which such a line can turn off, and Kconfig only warns about an
      # assignment that does not take: the -sprite image would lack the sprite.
      # A --module zmk-beacon from 0a64fc9 to before 7e86e58, whose
      # BEACON_SPRITE_NAME depends on BEACON_SPRITE, would also print the name.
      if [ -n "$SPRITE" ]; then die 2 "--kconfig: ${kv%%=*} does not combine with --sprite"; fi
      ;;
    CONFIG_?*=?*) ;;
    *) die 2 "--kconfig takes CONFIG_NAME=VALUE, not $kv" ;;
  esac
  case "${kv%%=*}" in *[!A-Za-z0-9_]*) die 2 "--kconfig: not a Kconfig symbol: ${kv%%=*}" ;; esac
done
case "$TAG" in *[!A-Za-z0-9._-]*) die 2 "--tag takes letters, digits, '.', '_' and '-'" ;; esac
# The image name would be the sprite build's, and the stamp drops a leading
# -sprite as the sprite build's (scripts/stamp.py).
[ "$TAG" != sprite ] || die 2 "--tag sprite is the sprite build's own suffix"

# Targets as board<TAB>shield. The groups come from build.yaml's shield names,
# never from a list here.
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
  # Zephyr takes extra modules after west's projects and keys them by name
  # (zephyr_module.py parse_modules), so each replaces the project of its name;
  # ZMK_EXTRA_MODULES is a CMake list (zmk app/CMakeLists.txt).
  if [ ${#MODULES_SORTED[@]} -gt 0 ]; then
    local extra=() name
    for name in "${MODULES_SORTED[@]}"; do
      extra+=("/workspace/.modules/$name")
      SUFFIX="$SUFFIX-${name#zmk-}"
    done
    CMAKE_ARGS+=("-DZMK_EXTRA_MODULES=$(IFS=';' && echo "${extra[*]}")")
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
# Cleared on every run: after a run without --sprite neither the GIF nor its
# name stays in .sprite/, and the .modules/ copies below, which have no
# --delete, keep no file of an earlier tree.
rm -rf "$CFG/.sprite" "$CFG/.kconfig" "$CFG/.modules"

# The container sees only the workspace, so the GIF is copied in under a fixed
# name. Its path and the sprite name reach the build in a Kconfig fragment
# (EXTRA_CONF_FILE), never as -DCONFIG_...: west prints the whole cmake
# command line when the configure step fails, and the name names the subject.
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
for i in ${MODULE_DIRS[@]+"${!MODULE_DIRS[@]}"}; do
  mkdir -p "$CFG/.modules/${MODULE_NAMES[$i]}"
  rsync -a --exclude '/.git' --exclude '/.claude/' --exclude '/firmware/' "${MODULE_DIRS[$i]}/" "$CFG/.modules/${MODULE_NAMES[$i]}/"
done

NEED_UPDATE=0
if [ ! -d "$CFG/.west" ] || [ ! -d "$CFG/zmk/app" ] || [ "$FORCE_UPDATE" -eq 1 ]; then
  NEED_UPDATE=1
fi

echo "=========================================="
echo " workspace   : $CFG"
echo " docker image: $IMAGE"
echo " west update : $([ "$NEED_UPDATE" -eq 1 ] && echo yes || echo 'no (cached; --update forces it)')"
for i in ${OWN_NAMES[@]+"${!OWN_NAMES[@]}"}; do
  j="$(module_index "${OWN_NAMES[$i]}")"
  if [ -n "$j" ]; then
    echo " module      : ${OWN_NAMES[$i]} ${MODULE_DIRS[$j]} @ ${MODULE_REVS[$j]} (--module, in place of the pin ${OWN_REVS[$i]:0:12})"
  else
    echo " module      : ${OWN_NAMES[$i]} @ ${OWN_REVS[$i]:0:12} (the pin in config/west.yml)"
  fi
done
for j in ${MODULE_NAMES[@]+"${!MODULE_NAMES[@]}"}; do
  [ -z "$(own_index "${MODULE_NAMES[$j]}")" ] || continue
  echo " module      : ${MODULE_NAMES[$j]} ${MODULE_DIRS[$j]} @ ${MODULE_REVS[$j]} (--module, not in config/west.yml)"
done
if [ "$LOGGING" -eq 1 ]; then echo " logging     : ${LOGGING_CONF[*]}"; fi
if [ "$RESET" -eq 1 ]; then echo " reset       : CONFIG_ZMK_SETTINGS_RESET_ON_START=y"; fi
if [ -n "$SPRITE" ]; then
  echo " sprite      : a $(wc -c <"$SPRITE" | tr -d ' ') byte GIF, a name of $(printf '%s' "$SPRITE_NAME" | wc -c | tr -d ' ') bytes (prospector only; neither printed)"
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
# Also a module a --module stands in for: the build takes the copy, but the
# stamp takes the pin's tree id from the clone, which a fresh pin lacks.
if [ ${#OWN_NAMES[@]} -gt 0 ]; then in_container pin "${OWN_NAMES[@]}"; fi
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
modules_rev=""
for i in ${OWN_NAMES[@]+"${!OWN_NAMES[@]}"}; do
  j="$(module_index "${OWN_NAMES[$i]}")"
  if [ -n "$j" ]; then
    rev="${MODULE_DIRS[$j]} @ ${MODULE_REVS[$j]} (--module)"
  else
    rev="$(git -C "$CFG/${OWN_PATHS[$i]}" log -1 --format='%h' 2>/dev/null || true)"
    rev="${rev:-?} (pin)"
  fi
  modules_rev="$modules_rev, ${OWN_NAMES[$i]} $rev"
done
for j in ${MODULE_NAMES[@]+"${!MODULE_NAMES[@]}"}; do
  [ -z "$(own_index "${MODULE_NAMES[$j]}")" ] || continue
  modules_rev="$modules_rev, ${MODULE_NAMES[$j]} ${MODULE_DIRS[$j]} @ ${MODULE_REVS[$j]} (--module)"
done
echo "revisions: zmk ${zmk_rev:-?}, zmk-keyboards ${keyboards_rev:-?}$modules_rev"
