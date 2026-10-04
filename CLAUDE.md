# CLAUDE.md

Claude Code notes: what breaks, and how to build, flash and read the devices. Usage:
[README.md](README.md). English only, per the fleet's
[doc-consistency policy](https://github.com/akira-toriyama/.github/blob/main/docs/doc-consistency-policy.md).

## What this repository is

- The ZMK user-config, at the repository root, of the **Cyboard Imprint** (board `assimilator-bt`,
  shields `imprint_left` / `imprint_right`, from Cyboard's `zmk-keyboards`) and its split central,
  the **Imprint Dongle** (ZMK's `xiao_ble/nrf52840/zmk`, Cyboard's shield `imprint_dongle`).
- The companion **Prospector Dongle** (`xiao_ble/nrf52840/zmk`, shield `prospector` of the own
  module [zmk-beacon](https://github.com/akira-toriyama/zmk-beacon), documented there) shows both
  halves' battery from the Imprint Dongle's status advertisement. It never advertises, pairs or
  connects (`CONFIG_ZMK_BLE=n`; a Mac scan saw nothing, 2026-09-26); on USB it is one CDC ACM port,
  product `Prospector Dongle`, no HID (2026-09-26). Its screen turns off after five minutes without
  a key press (`CONFIG_BEACON_SCREEN_OFF_AFTER_S`, default 300; seen with 20 s on 2026-10-04).
- [chord](https://github.com/akira-toriyama/chord) (separate repository), the macOS host bridge,
  reads the Imprint Dongle's vendor HID reports (`&vkey` 0x20, split battery 0x21).
- Low dependency: Python is stdlib only and runs on macOS's `/usr/bin/python3` (3.9: no `match`, no
  `X | Y` unions); the rest is shell; no Node or heavy toolchains. Tasks: `furrow list -r canon`.
- [docs/glossary.md](docs/glossary.md) is binding: canonical names only, never a `Don't call it:`
  synonym; a new or renamed term lands in the same PR as the code (devices: Cyboard Imprint,
  Imprint Dongle, Prospector Dongle; never "XIAO" or "Canon Dongle").

## Where to look

- `config/`: `imprint.keymap` (includes `behavior_macros.h` and the keymap-side `*.dtsi`; the halves'
  overlays include `ext_power_off.dtsi`), `west.yml`, the generated `vkey-aliases.toml`,
  `imprint.json` (keymap-drawer's physical layout), and confs and overlays named after shields: ZMK
  merges the `.conf` of every prefix of a shield name (`imprint.conf` serves all three imprint
  targets) but takes only the first matching overlay, so a `config/imprint.overlay` would silently
  replace `imprint_left.overlay`. [build.yaml](build.yaml): the only list of build targets.
  `patches/zmk/`, `patches/zephyr/`: applied before every build; their READMEs give reasons and PRs.
- `scripts/`: each header documents its flags and contracts; `flash-impl.sh` is the body of
  `flash-watch.sh` / `flash-reset.sh`. Build, Debugging and Invariants below place every script.
- [docs/recovery.md](docs/recovery.md): pairing recovery, new-unit provisioning. The glossary also
  builds the glossary site (`glossary.yml`): keep its entry format. [assets/README.md](assets/README.md):
  the sprite files. `keymap_drawer.config.yaml` configures keymap-drawer (output: `keymap-drawer/`).

## Build

- `./scripts/build-zmk.sh [all | imprint | <shield> | <board>:<shield>]... [flags]` (Docker; no
  target = all, `imprint` = build.yaml's `imprint*` shields). Flags (its header): `--update` (west
  update; otherwise zmk@main and the branches stay at the cached commits), `--clean`, `--reset`
  (`CONFIG_ZMK_SETTINGS_RESET_ON_START=y`: wipes settings and bonds at every boot), `--logging`,
  `--kconfig CONFIG_X=V`, `--tag <name>`, `--beacon <dir>` (a zmk-beacon tree, not the pin), `--sprite`.
- Images: `firmware/<shield>[-sprite][-logging][-kconfig][-beacon][_RESET][-<tag>].uf2`; a bare
  `<shield>.uf2` / `<shield>_RESET.uf2` (what flash-watch.sh, flash-reset.sh and `flash-dongle.sh
  <device>` take) is always a pinned build. West topdir `~/.cache/zmk-canon/cfgrepo` (each run syncs
  `config/`, `patches/`, `scripts/`, `build.yaml` into it); per image, `build/<image name>/` keeps
  `build.log` (FLASH/RAM at its end) and `zephyr/{.config,zephyr.dts,zmk.map,zmk.elf}`.
- Never edit the cached `modules/zmk-beacon`: builds without `--beacon` check out the pin and stop
  on local changes. `zmk-west.sh update` takes the patches off first (west refuses to move a patched
  file); `patch` skips applied ones and fails on a stale one; a changed patch file needs the cached
  tree reset once ([patches/zmk/README.md](patches/zmk/README.md)).
- CI: `build.yml` (PRs, main, Mondays for zmk@main breaks) calls the local reusable `zmk-build.yml`,
  not ZMK's `build-user-config.yml`, which applies no patches (`&vkey` would not resolve) and could
  run only at a SHA (fleet zizmor policy). Keep the job id `build` and the job name: they form the
  required checks `build / Build (<board>, <shield>)`. Release: a push to main that moves the
  version upserts a rolling draft (`release.yml`) with the `ASSETS` allowlist's images, tagged when
  published by hand; a new build.yaml target joins `ASSETS`, or the draft job fails.

## Debugging and device operations

| Goal | Command | Healthy result |
| --- | --- | --- |
| Images | `./scripts/build-zmk.sh <targets> [--logging]` | `images:` lines `firmware/<name>.uf2  <12 hex>  FLASH … RAM …`, then `revisions: zmk …, zmk-keyboards …, zmk-beacon <hash> (pin)` |
| Flash either dongle, no double-tap | `./scripts/flash-dongle.sh <prospector \| imprint_dongle \| image.uf2>` (`--dry-run` checks only, `--wait N` for a dongle a KVM switch hid, `--reset` for `*_RESET*`) | last line `[HH:MM:SS] DONE <device> serial=… <image> sha256=<the build summary's 12 hex>`, exit 0; then the display or both halves typing (re-enumeration does not show which image booted) |
| Flash the halves and the Imprint Dongle | `./scripts/flash-watch.sh` or `./scripts/flash-reset.sh` (`--yes` skips the prompt), then double-tap one device at a time, the left half before the right (the mount order decides which is which); after a reset build, the order of [docs/recovery.md](docs/recovery.md) B (from source, not yet run on hardware) | `[HH:MM:SS] ALL DONE: left + right + dongle` (flash-reset.sh adds ` (NVS wiped)`), exit 0 |
| Find the dongles | `python3 scripts/dongle.py list` | each dongle with its `/dev/cu.*` port, `location=… serial=…`, `port free`; `/Volumes/XIAO-SENSE  not mounted`; `flashers  none running` |
| See the Prospector Dongle's screen, dark or lit | `python3 scripts/dongle.py shot --out <scratch>/shot.png` (never inside a git work tree; refuses while a log reader holds the port), then Read the PNG | stdout the PNG's path, stderr `dongle.py shot: 280x240 in N bands, CRC-32 ok, …` |

- Timings: Imprint Dongle (2026-09-27, t-eray, #222) mount 2.2-2.6 s, copy 9.5-12.2 s, back 0.7-1.3 s.
  An unchanged image copies in about 3 s, not 24 s (Prospector Dongle, bootloader 0.6.1, 2026-09-26:
  it skips matching pages and resets after the last block, `src/flash_nrf5x.c`): not a truncated copy.
- `python3 scripts/dongle.py log prospector imprint_dongle --seconds N [--grep RE] [--out FILE]`:
  lines `MM-DD HH:MM:SS.mmm <device>`, a bar, the text; exit 0 at the deadline, 1 if a device never
  appeared; 115200 only; follows a dongle through a reboot (start it before a flash for the boot
  log); drops key-event lines unless `--raw`. ZMK logs there only in a `--logging` image (a 4 KiB
  CDC ring keeps the boot log; ZMK at INFO); zmk-beacon's CLAUDE.md explains its periodic lines.
  Never write log output into a repository, nor paste `--raw` lines anywhere: they carry keystrokes.
- Split battery and connection lines are ZMK DEBUG: build `imprint_dongle --logging --kconfig
  CONFIG_ZMK_LOGGING_MINIMAL=n`, flash `firmware/imprint_dongle-logging-kconfig.uf2`, read with
  `--grep '(?i)battery level|connected'`. DEBUG overflows the boot log and logs keycodes:
  power-cycle a half to see a connect; flash the product image back afterwards. A plain `--logging`
  image shows levels only in zmk-beacon's minute line (`--grep 'battery [0-9]+/[0-9]+'`).

## Invariants

- **The west manifest is [config/west.yml](config/west.yml), with the repository root as topdir**,
  so never `west init` / `west update` in the repository: the work tree would take clones of zmk,
  zephyr and every module (build-zmk.sh builds in its workspace copy). Besides ZMK it lists two
  modules (zmk-keyboards' imported manifest adds `zmk-pmw3610-driver`):
  - **Cyboard `zmk-keyboards` at branch `zephyr-4.1`, never `main`**: since 2026-07-07 `main` pins
    ZMK `v0.3.0` with the HWv1 `assimilator-bt` (`boards/arm/`), which fails against zmk@main with
    `Kconfig/soc/Kconfig.defconfig not found` on the two assimilator-bt targets (a partial red on
    2026-07-07, while canon's own `imprint_dongle` shield stayed green). The HWv2 board is on
    `zephyr-4.1`, as Cyboard's own west.yml says; kept 2026-07-30 (t-wz4k).
  - **Own `zmk-beacon`, pinned by commit SHA** so that canon takes a change without a zmk-beacon
    release (2026-09-26, t-5gxp): the `prospector` shield and the Imprint Dongle's status
    broadcaster (payload: its `src/status_payload.h`). Bump the SHA by hand after a merge there.
- **ZMK tracks `main`, never a tag**, against ZMK's advice: the HWv2 `assimilator-bt` needs Zephyr's
  new hardware model, and a ZMK tag fails in `arch.cmake` with `Could not find ARCH=cyboard`.
- **No local boards or shields**: `imprint_dongle` went upstream with Cyboard#19 (merged
  2026-07-28); canon's part is `config/imprint_dongle.{conf,overlay}`.
- **eiji: [config/eiji_macros.dtsi](config/eiji_macros.dtsi) is the single source** of the `en_*`
  labels: `python3 scripts/gen-eiji-drawer-map.py` writes the AUTO-GENERATED block of
  `keymap_drawer.config.yaml` (never edit between its markers), checked by `verify-eiji-sync.yml`.
- **vkey: `&vkey <id>` in [config/imprint.keymap](config/imprint.keymap) is the single source**
  (node: `config/imprint_behaviors.dtsi`): `python3 scripts/gen-vkey-aliases.py` writes
  `config/vkey-aliases.toml` for chord's `[v-key-aliases]` (pasted by hand into dotfiles), checked
  by `verify-vkey-sync.yml`. Ids: `0x01` and a 30-id block per Vkey layer at `0x10`, `0x30`, `0x50`,
  `0x70` (last `0x8D`). `0xA0`-`0xBF` is the ist dongle's (zmk-hid-host): chord maps ids in one
  namespace per host, so a reused id fires ist's buttons; `decode()` refuses other ids.
- **The USB product string `Imprint Dongle` is a contract**: chord's `VKeyHIDSource`, flash-dongle.sh
  and dongle.py (`DEVICES`) find the dongle by it, as VID/PID `0x1D50`/`0x615E` are ZMK's defaults
  on all three dongles (the Imprint and ist dongles on one Mac, 2026-09-24; the Prospector Dongle's
  shield sets only the product string). It comes from the upstream shield's `ZMK_KEYBOARD_NAME`:
  never set `CONFIG_ZMK_KEYBOARD_NAME` for it in `config/`; an upstream rename changes chord's
  `productName` and `DEVICES` in `scripts/dongle.py` at once.
- **Cyboard's `ZMK_RGB_UNDERGLOW` default `y` reaches every target**: zmk-keyboards'
  `boards/shields/imprint/Kconfig.defconfig` sets it outside any `SHIELD_` guard, so a target
  without a `zmk,underglow` chosen node fails with `#error` in `rgb_underglow.c` (2026-09-25). Every
  non-imprint conf sets `CONFIG_ZMK_RGB_UNDERGLOW=n` (`config/prospector.conf` does).
- **The Imprint Dongle builds with `CONFIG_BT_EXT_ADV` and needs `CONFIG_BT_EXT_ADV_MAX_ADV_SET=2`**
  (`config/imprint_dongle.conf`): `CONFIG_BEACON_STATUS_BROADCAST` selects it for a second
  advertising set, and the host serves ZMK's legacy `bt_le_adv_start()` from the same pool; a pool
  of 1 fails zmk-beacon's `BUILD_ASSERT`. Costs: about 34 KB flash and 11 KB RAM, the host on
  extended HCI commands, and an extended scan following nearby AuxPtr fields, where ZMK's Zephyr
  fork lacks upstream 5ce9d0c621 (an assert on an invalid `chan_idx`; if it bites, carry it in
  `patches/zephyr/`). Hardware 2026-09-26/27 (t-eray): reconnects unchanged over 5 reboots and a
  half's power cycle, 0 advertising errors, 255-269 payloads a minute.
- **Both dongles mount the same `XIAO-SENSE` bootloader volume, and flash-watch.sh / flash-reset.sh
  copy `imprint_dongle*.uf2` onto the first XIAO bootloader they see**: never put the Prospector
  Dongle into its bootloader while they run, nor both dongles at once. flash-dongle.sh guards this
  (their shared lock; no start while `XIAO-SENSE` is mounted; a copy only onto the disk at that
  dongle's USB location, which its bootloader keeps, 2026-09-26; details: its header). The first
  image with the 1200 baud entry, and a failed run, go on by double-tap + `cp -X` (docs/recovery.md).
- **A dongle port's rate is a command**: 1200 baud reboots either dongle into its UF2 bootloader,
  2400 makes the Prospector Dongle send its screen (zmk-beacon's
  `CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD`, on in its shield and, since 2026-09-27, in
  `config/imprint_dongle.conf`, whose product image has the port too; `CONFIG_BEACON_SCREEN_DUMP`).
  Any program that sets the rate does it (`stty`, a serial monitor): never open a dongle port at
  either rate by hand. Find ports by USB product string, never by VID/PID or a `/dev/cu.usbmodem*`
  name (it follows the USB location). The option depends on `USB_CDC_ACM`, without which `=y` drops
  out with a mere warning: after a ZMK bump, grep it in `build/imprint_dongle/zephyr/.config`.
- **A split peripheral's slot index is the order the dongle first hears it, persisted**: ZMK's
  `zmk_ble_put_peripheral_addr()` (`app/src/ble.c`) saves a new advertiser in the first free slot,
  before pairing and even if pairing fails, and `reserve_peripheral_slot()` (`central.c`) maps it
  back until an NVS reset (read 2026-10-04, ZMK 5b51501f). Consumers: chord's split battery
  `source` and zmk-beacon's `src/status_broadcaster.c` (slot 0 → the left byte). Slot 0 is the left
  half (2026-09-27, t-eray); after a reset, the left half pairs first (docs/recovery.md B).
- **Generated and tool-managed files are never formatted (`.prettierignore`) or edited where
  generated**: the AUTO-GENERATED block of `keymap_drawer.config.yaml`, `config/vkey-aliases.toml`,
  `keymap-drawer/imprint.{yaml,svg}`, `config/imprint.json`. Draw keymap commits `keymap-drawer/`
  onto the branch after a push that changes the keymap's inputs: pull before the next push.
- **README.md is the user's**: without an instruction, fix facts only, never restructure it.
- **The layout is constrained**: `config/` and `build.yaml` stay at the root (ZMK and west expect
  them); a local board or shield needs root `boards/` and `zephyr/module.yml` again plus the
  `-DBOARD_ROOT` / `-DDTS_ROOT` flags c49da40 removed (2026-07-30). `keymap_drawer.config.yaml`
  beside `keymap-drawer/` is keymap-drawer's default; `scripts/` is not split further. glyph's
  `[[packages]]` is not used (2026-09-10, t-ptp3): the four images are one product (one manifest,
  patch set and draft; t-tbaf), and split, a patch-only fix (e.g. #148) would move no version.

## Privacy: the sprite

- **This repository is public; the sprite GIF is personal, and the sprite name names its subject.**
  Never put a GIF or anything made of one (frames, C arrays, previews, `shot` PNGs) into a commit,
  PR, issue, CI or release, nor its subject, file name or sprite name into their text or a doc.
- Local only: `./scripts/build-zmk.sh prospector --sprite <gif>` writes
  `firmware/prospector-sprite.uf2` (zmk-beacon's `CONFIG_BEACON_SPRITE_GIF`); the CI and release
  `prospector.uf2` carries neither sprite nor name, so flashing it removes both. The GIFs live in
  the main checkout's git-ignored `assets/` ([assets/README.md](assets/README.md): the ignore rules,
  `SOURCES.md`); a worktree has only its two committed files, so pass the main checkout's path.
- [assets/sprite-name.sh](assets/sprite-name.sh) derives the name from the file name (t-er81);
  build-zmk.sh passes it as `CONFIG_BEACON_SPRITE_NAME` in a Kconfig fragment
  (`cfgrepo/.sprite/sprite.conf`, `EXTRA_CONF_FILE`), never `-DCONFIG_...`, which west prints when
  the configure step fails (reproduced 2026-09-29), and prints only the GIF's size and the name's
  length. `cfgrepo/.sprite/` and a sprite build's directory (`zephyr/.config`, the image) hold the
  GIF and the name: never print or paste from them. The screen layout (zmk-beacon's README, the
  glossary) is the user's pick (t-dzxf; t-er81, layout M of twelve trials): change it only on request.

## Commits, pull requests, fleet files

- Commits ([CONTRIBUTING.md](https://github.com/akira-toriyama/.github/blob/main/CONTRIBUTING.md)):
  glyph's `<:gemoji:>[(scope)]<sigil> <subject>`; the sigil is the version signal (`=` none, `~`
  patch, `^` minor, `!` major; `%` acts as `!` past 1.0), the gemoji decides nothing (`glyph
  emoji`); English imperative subjects, lowercase start; a PR title (the squash subject) is linted
  too. `glyph lint --range origin/main..HEAD` before pushing; `glyph hook install` once per clone.
- PR bodies end with `SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/<id>.md <lane>`.
- Public repository on free Actions minutes: PR gates are deterministic checks only (build,
  commit-lint, shellcheck, verify-eiji-sync, verify-vkey-sync, draw-keymap's `fail_on_error`,
  actionlint, zizmor, repo-policy, taplo, the glossary build); never add a workflow that calls a
  paid API; Claude reviews run locally. The main ruleset requires `lint / lint` and the three
  imprint builds, not prospector's (2026-10-04).
- Fleet-managed, never edited here (fleet-sync in akira-toriyama/.github overwrites them):
  `.github/workflows/{actionlint,commit-lint,repo-policy,taplo,task-status,version-preview,zizmor}.yml`,
  `.github/zizmor.yml`, `.github/dependabot.yml`, `docs/commit-convention.md`. `glyph.toml` came
  from `glyph init --gemoji --v1-window` and carries a hand edit (#197): edit it, never regenerate it.
