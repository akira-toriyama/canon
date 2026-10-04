<!--
Title = <:gemoji:>[(scope)]<sigil> <subject> — glyph.toml decides (docs/commit-convention.md).
The sigil is the version signal; always write one: = none / ~ patch / ^ minor / ! major.
  :lipstick:(keymap)~ name the arrow layers after their trigger key
A single-commit PR squash-merges with the commit message as the title — keep them in sync.
-->

## What & why

<!-- The change in a sentence or two, and the reason for it. -->

## Verification

<!-- Keep what applies, delete the rest. -->

- [ ] CI green: Build, commit-lint, actionlint, zizmor, repo-policy; and, when their files change, ShellCheck, taplo, Verify eiji map sync, Verify vkey aliases sync, Draw keymap, Deploy glossary site
- [ ] Keymap, behavior, config or patch change: `./scripts/build-zmk.sh` builds (paste its closing `images:` and `revisions:` lines)
- [ ] `config/eiji_macros.dtsi` changed: `python3 scripts/gen-eiji-drawer-map.py` re-run, `keymap_drawer.config.yaml` committed
- [ ] `&vkey` ids in `config/imprint.keymap` changed: `python3 scripts/gen-vkey-aliases.py` re-run, `config/vkey-aliases.toml` committed
- [ ] Generated and tool-managed files not hand-edited or reformatted: the AUTO-GENERATED block of `keymap_drawer.config.yaml`, `config/vkey-aliases.toml`, `keymap-drawer/imprint.{yaml,svg}` (Draw keymap commits them), `config/imprint.json`
- [ ] Docs follow the change: `README.md`, `CLAUDE.md`, and `docs/glossary.md` for a term added or renamed
- [ ] Hardware, for a firmware change: device (Cyboard Imprint, Imprint Dongle, Prospector Dongle), image, what was seen, date; or why no flash is needed. Never a picture of a sprite build (a `shot` PNG or a photo) or the sprite's name here.

## Notes for reviewers

<!-- Anything subtle, deferred, or risky — state it explicitly rather than leaving it implicit. -->

<!--
Task footer, so the furrow task's status follows this PR: a line of its own that starts with the
directive SetStatus-task:, then the task's body URL
https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/<id>.md and an optional <lane>.
furrow reads this comment too, so no line in it starts with the directive. With <lane>: opening the
PR nudges a task not yet in a terminal lane to in-progress, and the merge applies <lane> (e.g.
`done`; `furrow board` lists the lanes). Without <lane>: open and merge only annotate the task body.
Non-blocking: a bad id or lane comments on the PR but never blocks the merge.
-->
