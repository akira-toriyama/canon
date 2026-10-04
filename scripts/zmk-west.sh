#!/usr/bin/env bash
#
# The in-container half of canon's firmware build: scripts/build-zmk.sh runs
# each step in its own `docker run` of zmkfirmware/zmk-build-arm, and
# .github/workflows/zmk-build.yml runs them as job steps in the same image.
# The west topdir is this script's parent directory (the checkout in CI, the
# workspace copy $ZMK_WS/cfgrepo locally), with the manifest in config/.
#
#   zmk-west.sh pairs                         board<TAB>shield per build.yaml entry
#   zmk-west.sh update [west update args]     west init if needed, patches out, west update
#   zmk-west.sh pin <project>                 <project> at its manifest revision, unedited
#   zmk-west.sh patch                         apply patches/<tree>/*.patch (idempotent)
#   zmk-west.sh build <board> <shield> <suffix> [cmake args]
#                                             west build into build/<shield><suffix>,
#                                             its output also in build.log there
#
# pairs needs only awk (host or runner); the rest need the image's west.
set -euo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOP"

# The west projects canon patches, named by their west path as patches/<tree>/
# names them. A patched project goes through update, never pin: west refuses
# to check out over a patched file.
TREES=(zmk zephyr)

usage() {
  awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "${BASH_SOURCE[0]}" >&2
  exit 2
}

# The ZMK user-config template's include: list, board and shield in either
# order within a "- " item; comment lines are skipped. A top-level
# board:/shield: matrix is not supported.
cmd_pairs() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-[[:space:]]/ { if (b != "") print b "\t" s; b=""; s="" }
    /^[[:space:]]*(-[[:space:]]*)?board:[[:space:]]/  { t=$0; sub(/.*board:[[:space:]]*/,  "", t); b=t }
    /^[[:space:]]*(-[[:space:]]*)?shield:[[:space:]]/ { t=$0; sub(/.*shield:[[:space:]]*/, "", t); s=t }
    END { if (b != "") print b "\t" s }
  ' "$TOP/build.yaml"
}

# The trees belong to another uid than the container's user (a bind mount
# locally, the runner's checkout in CI's job container), and git refuses them
# as dubious ownership. The setting lives in the container's HOME.
trust_workspace() {
  if ! git config --global --get-all safe.directory 2>/dev/null | grep -qxF '*'; then
    git config --global --add safe.directory '*'
  fi
}

# One tree's patches as absolute paths (git -C <tree> apply resolves a relative
# one against <tree>) in C byte order, the order they go on; "-r" gives the
# order they come off. The one ordering constraint today:
# usb-hid-prime-on-ready before vkey-report, both change app/src/usb_hid.c.
patch_list() {
  local tree=$1 p
  shift
  for p in "$TOP/patches/$tree"/*.patch; do
    if [ -e "$p" ]; then printf '%s\n' "$p"; fi
  done | LC_ALL=C sort "$@"
}

cmd_update() {
  trust_workspace
  echo "=== west init/update"
  [ -d .west ] || west init -l config
  # west update refuses to check out a revision that changes a file a patch
  # modified (zmk 9ebbeff0 -> 5b51501f changed app/src/split/bluetooth/Kconfig,
  # 2026-09-27), so the patches come out first and cmd_patch puts them back.
  # Only a patch the working tree carries and the index does not: patches go
  # on without --index, so one that upstream merged is in both and stays.
  local tree p
  for tree in "${TREES[@]}"; do
    [ -e "$tree/.git" ] || continue
    while IFS= read -r p; do
      if git -C "$tree" apply --reverse --check "$p" >/dev/null 2>&1 &&
        ! git -C "$tree" apply --reverse --check --cached "$p" >/dev/null 2>&1; then
        git -C "$tree" apply --reverse "$p"
        echo "=== UNPATCH $tree: $(basename "$p")"
      fi
    done < <(patch_list "$tree" -r)
  done
  west update "$@"
}

# A hand checkout in a cached clone, or a pin bump without a full update,
# would otherwise go into the image unnoticed. Updates this one project only:
# a full update also moves the branches the manifest follows (zmk@main).
cmd_pin() {
  [ $# -eq 1 ] || usage
  local project=$1 path rev head
  trust_workspace
  read -r path rev < <(west list -f '{path} {revision}' "$project")
  head="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  if [ "$head" != "$rev" ]; then
    echo "=== PIN $project: ${head:-not cloned} -> $rev"
    west update "$project"
  fi
  if [ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]; then
    echo "error: $path has local changes to tracked files; an image takes $project at its pin only." >&2
    echo "  Build a local checkout with build-zmk.sh --beacon <dir>, or discard the changes: git -C <workspace>/$path checkout -- ." >&2
    exit 1
  fi
}

cmd_patch() {
  trust_workspace
  local tree p name
  for tree in "${TREES[@]}"; do
    while IFS= read -r p; do
      name="$(basename "$p")"
      if git -C "$tree" apply --reverse --check "$p" >/dev/null 2>&1; then
        echo "=== PATCH $tree: $name (already applied)"
      elif git -C "$tree" apply --check "$p" >/dev/null 2>&1; then
        git -C "$tree" apply "$p"
        echo "=== PATCH $tree: $name (applied)"
      else
        echo "error: patches/$tree/$name applies neither forward nor in reverse to $tree:" >&2
        echo "  upstream changed the lines it touches; update the patch, or drop it if upstream merged it." >&2
        echo "  Locally also when the patch file changed after the tree was patched. Unless the tree holds an edit" >&2
        echo "  you still need, reset it: git -C ~/.cache/zmk-canon/cfgrepo/$tree checkout -- . and clean -fd" >&2
        echo "  (\$ZMK_WS/cfgrepo when ZMK_WS is set), or run build-zmk.sh --clean." >&2
        git -C "$tree" apply --check -v "$p" >&2 || true
        exit 1
      fi
    done < <(patch_list "$tree")
  done
}

cmd_build() {
  [ $# -ge 3 ] || usage
  local board=$1 shield=$2 suffix=$3 dir
  shift 3
  # An empty shield would make $dir build/ itself, and the rm below would
  # take every cached build with it.
  if [ -z "$board" ] || [ -z "$shield" ]; then usage; fi
  dir="build/$shield$suffix"
  trust_workspace
  # Registers Zephyr in the CMake user package registry for zmk/app's
  # find_package(Zephyr); the registry lives in HOME, new in each container.
  west zephyr-export
  # Emptied here: west's pristine step (-p) would delete build.log under tee.
  # With the directory empty, -p finds no build to clean.
  rm -rf "$dir"
  mkdir -p "$dir"
  echo "=== BUILD $board / $shield$suffix"
  west build -p -s zmk/app -d "$dir" -b "$board" -- \
    -DSHIELD="$shield" -DZMK_CONFIG="$TOP/config" "$@" 2>&1 | tee "$dir/build.log"
  echo "=== DONE $shield$suffix"
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
  pairs) cmd_pairs ;;
  update) cmd_update "$@" ;;
  pin) cmd_pin "$@" ;;
  patch) cmd_patch ;;
  build) cmd_build "$@" ;;
  -h | --help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "${BASH_SOURCE[0]}" ;;
  *) usage ;;
esac
