# assets

This directory holds only this README and `sprite-name.sh`. The personal files
for local builds live off the repository, on the external drive, so that a
reinstall of the Mac keeps them and every checkout and worktree uses the same
path:

- `/Volumes/HDD/assets/canon/prospector/sprites/`: sprite GIFs for the
  Prospector Dongle, and `SOURCES.md` with each file's source URL, so a lost
  file can be fetched again.
- `/Volumes/HDD/assets/canon/prospector/shots/`: `scripts/dongle.py shot` PNGs
  of a sprite build.

Usage and rules:

- `./scripts/build-zmk.sh prospector --sprite /Volumes/HDD/assets/canon/prospector/sprites/<name>.gif`
  builds `firmware/prospector-sprite.uf2`. Only a sprite build needs the drive
  connected. zmk-beacon's README lists which GIFs work.
- The name under the HP bar comes from the GIF's file name:
  `sprite-name.sh <gif>` drops the extension, trims whitespace at both ends
  and upper-cases the first letter (`my sprite.gif` shows `My sprite`), and
  the build passes that to zmk-beacon. Printable ASCII only, no double quote,
  backslash or `??`; 15 glyphs fit, a longer name is cut. To show another
  name, rename the file.
- The drive is exFAT, where macOS stores a file's extended attributes in a
  `._<name>` sidecar file. Copy files onto it with `cp -X`, clear the sidecars
  with `dot_clean -m <dir>`, and give `--sprite` one file, never a `*.gif`
  glob, which would match a sidecar too.
- This repository is public: never copy a personal file into it, and never
  commit anything made from one (frames, C arrays, previews, shots). The
  ignore rules (everything in this directory but its two files, and GIFs
  anywhere in any letter case) stay as a guard.
