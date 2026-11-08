# assets

This directory holds only this README and `sprite-name.py`. The personal files
for local builds stay off the repository:

- The sprite GIFs for the Prospector Dongle are `<number>.gif` files in a sparse
  clone that only the private dotfiles-private names, in `sprite-sender/`
  (`clone.sh` makes the clones, and `sender.json` is the sprite sender's config:
  zmk-beacon's README, "The sprite sender"). The same absolute path holds from
  any checkout or worktree, and a reinstall of the Mac gets it back from
  `clone.sh`. This repository names neither the clone's repository nor its path.
- The sprite sender's state file, which holds the number of the GIF tried last,
  sits next to that config, ignored by git: the number names the subject.
- `scripts/dongle.py shot` PNGs of a sprite build go to
  `~/.cache/zmk-canon/shots/`. Run `mkdir -p` on it first: `shot --out` makes no
  parent and refuses a path inside a git work tree.

Usage and rules:

- `./scripts/build-zmk.sh prospector --sprite <collection>/<number>.gif` builds
  `firmware/prospector-sprite.uf2`. Give `--sprite` one file. zmk-beacon's README
  lists which GIFs work.
- The name above the HP bar comes from `sprite-name.py <gif>` (its header), by
  the rule the sprite sender runs by. For a `<number>.gif`, it is the name
  dictionary's katakana name of that number when it is 15 bytes of UTF-8 at most
  and all in the katakana font, composed, else its English name, whole (a
  gender sign at its end folded to a space and `F` or `M`, a typographic
  apostrophe to `'`, nothing else: zmk-beacon's `fold_english`). The name
  dictionary is the species names CSV of the config that `--sender-config` gives,
  else `$SPRITE_SENDER_CONFIG`, which dotfiles sets.
- Otherwise the name is the file name with the extension dropped, spaces and tabs
  trimmed at both ends, the first letter upper-cased (`my sprite.gif` shows
  `My sprite`), cut to 15 bytes and trimmed again: printable ASCII only, no double
  quote, backslash or `??`. A `<number>.gif` then shows the number. To show another
  ASCII name, copy the GIF to a file of that name, outside any repository.
- The script says on stderr which alphabet it chose, and why it fell back to the
  file name when the config is to blame, and the build passes the name to
  zmk-beacon. The device draws a katakana name in the katakana font, an ASCII name
  in unscii 16 (zmk-beacon c92ffcf).
- This repository is public: never copy a personal file into it, and never
  commit anything made from one (frames, C arrays, previews, shots). The
  ignore rules (everything in this directory but its two files, and GIFs
  anywhere in any letter case) stay as a guard.
