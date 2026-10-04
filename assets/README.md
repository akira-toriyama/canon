# assets

Personal files for local builds. Everything in this directory except this
README and `sprite-name.sh` is git-ignored, and GIFs (any case of `.gif`) are
ignored anywhere in the repository.

- Sprite GIFs for the Prospector Dongle:
  `./scripts/build-zmk.sh prospector --sprite assets/<name>.gif` builds
  `firmware/prospector-sprite.uf2`. zmk-beacon's README lists which GIFs work.
- The name under the HP bar comes from the GIF's file name:
  `sprite-name.sh <gif>` drops the extension, trims whitespace at both ends
  and upper-cases the first letter (`my sprite.gif` shows `My sprite`), and
  the build passes that to zmk-beacon. Printable ASCII only, no double quote,
  backslash or `??`; 15 glyphs fit, a longer name is cut. To show another
  name, rename the file.
- This repository is public: never force-add a file from here, and never
  commit anything made from one (frames, C arrays, previews).
- Keep each file's source URL in `assets/SOURCES.md` (ignored like the rest),
  so a lost file can be fetched again.
- A git worktree gets only this README and `sprite-name.sh`; the personal files
  live in the main checkout (from a worktree, pass `--sprite` their absolute
  path).
