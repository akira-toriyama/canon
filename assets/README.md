# assets

This directory holds only this README and `sprite-name.py`. The personal files
for local builds live off the repository, on the external drive, so that a
reinstall of the Mac keeps them and every checkout and worktree uses the same
path:

- `/Volumes/HDD/assets/canon/prospector/sprites/`: sprite GIFs for the
  Prospector Dongle, and `SOURCES.md` with each file's source URL, so a lost
  file can be fetched again. Also the sprite sender's `sender.json` (the
  collection's front and back directories, the state file and the order
  file, as paths relative to it, and the range of the order's places the
  rotation keeps, which with this order file are the species' numbers, and
  the name dictionary; zmk-beacon's README, "The sprite sender"), its state
  file, which names the GIF tried last, its order file, which names the GIFs
  in National Pokédex order, one a line (built from `SOURCES.md`'s
  number-and-name table; t-9aga), and the name dictionary `names.json`, the
  katakana and English names by number, which zmk-beacon's
  `tools/name_dictionary.py` writes from PokeAPI's species names CSV
  (`SOURCES.md` has the source; t-rq9h). The dictionary names the
  collection's subjects, so it stays off every repository like the order
  file.
- `/Volumes/HDD/assets/canon/prospector/shots/`: `scripts/dongle.py shot` PNGs
  of a sprite build.

Usage and rules:

- `./scripts/build-zmk.sh prospector --sprite /Volumes/HDD/assets/canon/prospector/sprites/<name>.gif`
  builds `firmware/prospector-sprite.uf2`. Only a sprite build needs the drive
  connected. zmk-beacon's README lists which GIFs work.
- The name above the HP bar is the name dictionary's katakana name when the
  HP bar can show it, else the GIF's file name, looked up by
  `sprite-name.py <gif>` as the sprite sender does (its header): the GIF's
  directory is the `front` of the `sender.json` above it, the GIF's position
  among the order file's names is its place, and the dictionary's name of that place is
  taken when it is composed, 15 bytes of UTF-8 at most and all in the
  katakana font. Otherwise the file name with the extension dropped,
  whitespace trimmed at both ends, the first letter upper-cased
  (`my sprite.gif` shows `My sprite`), cut to 15 bytes: printable ASCII only,
  no double quote, backslash or `??`. The script says on stderr which it
  chose, and the build passes the name to zmk-beacon. To show another ASCII
  name, rename the file. The device draws a katakana name in the katakana
  font, an ASCII name in unscii 16 (zmk-beacon c92ffcf).
- The drive is exFAT, where macOS stores a file's extended attributes in a
  `._<name>` sidecar file. Copy files onto it with `cp -X`, clear the sidecars
  with `dot_clean -m <dir>`, and give `--sprite` one file, never a `*.gif`
  glob, which would match a sidecar too.
- This repository is public: never copy a personal file into it, and never
  commit anything made from one (frames, C arrays, previews, shots). The
  ignore rules (everything in this directory but its two files, and GIFs
  anywhere in any letter case) stay as a guard.
