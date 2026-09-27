# assets

Personal files for local builds. Everything in this directory except this
README is git-ignored, and GIFs (any case of `.gif`) are ignored anywhere in
the repository.

- Sprite GIFs for the Prospector Dongle:
  `./scripts/build-zmk.sh prospector --sprite assets/<name>.gif` builds
  `firmware/prospector-sprite.uf2`. zmk-beacon's README lists which GIFs work.
- This repository is public: never force-add a file from here, and never
  commit anything made from one (frames, C arrays, previews).
- Keep each file's source URL in `assets/SOURCES.md` (ignored like the rest),
  so a lost file can be fetched again.
- A git worktree gets only this README; the files live in the main checkout.
