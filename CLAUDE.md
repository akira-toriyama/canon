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
  halves' battery from the Imprint Dongle's status advertisement, under a sprite (its back view
  while the advertisement reports a modifier held). It scans
  passively for that, and since zmk-beacon's sprite receiver (`CONFIG_BEACON_SPRITE_RECEIVE`, the
  shield's default) it also advertises connectably as `Prospector Dongle` so that the sprite sender
  (zmk-beacon's `tools/sprite-sender`, run once a day by a LaunchAgent in dotfiles, config and state
  next to the GIFs on the external drive; the glossary) can write a sprite pack into its sprite room
  (2026-10-12; daily on hardware since 2026-10-13); it never pairs (`CONFIG_ZMK_BLE=n`). On USB it is
  one CDC ACM port, product `Prospector Dongle`, no HID (2026-09-26). Its screen turns off after five minutes without
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
  overlays include `lantern_rail.dtsi` and `cdc_acm_port.dtsi`), `west.yml`, the generated `vkey-aliases.toml`,
  `imprint.json` (keymap-drawer's physical layout), and confs and overlays per shield: ZMK merges the
  `.conf` of every shield-name prefix (`imprint.conf` serves all three imprint targets) but takes only
  the first matching overlay: a `config/imprint.overlay` would silently replace `imprint_left.overlay`
  (`app/boards/post_boards_shields.cmake`). [build.yaml](build.yaml): the only list of build targets.
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
  `--kconfig CONFIG_X=V`, `--tag <name>`, `--module <dir>` (a local tree of an own module in place
  of its pin, or of one not pinned yet; repeatable), `--sprite`.
- Images: `firmware/<shield>[-sprite][-logging][-kconfig][-<module>…][_RESET][-<tag>].uf2`
  (`-<module>` is the name without `zmk-`: `-beacon`, `-lantern`, in name order); a bare
  `<shield>.uf2` / `<shield>_RESET.uf2` (what flash-watch.sh, flash-reset.sh and `flash-dongle.sh
  <device>` take) is always a pinned build. West topdir `~/.cache/zmk-canon/cfgrepo` (each run syncs
  `config/`, `patches/`, `scripts/`, `build.yaml` into it); per image, `build/<image name>/` keeps
  `build.log` (FLASH/RAM at its end) and `zephyr/{.config,zephyr.dts,zmk.map,zmk.elf}`.
- Every image carries the firmware stamp (Invariants): `zmk-west.sh build` sets
  `CONFIG_USB_DEVICE_MANUFACTURER` from `scripts/stamp.py stamp` and runs `stamp.py verify` after
  the build, which fails the run when `config/` files the build read and the stamp's table differ
  or `.config` lacks the stamp (Zephyr only warns about a value that does not take); its line
  `=== STAMP <image>: ZMK Project (canon <shield> <12 hex><variant>) (N config files, M patches)`
  ends `build.log`. `python3 scripts/stamp.py digest <shield> [--ref origin/main] [--files]`
  prints the digest and table by hand.
- Never edit the cached clone of an own module (`modules/zmk-beacon`, `modules/zmk-lantern`: the
  projects `python3 scripts/stamp.py pins` lists): every build checks each out at its pin (one a
  `--module` replaces too: the stamp takes the pin's tree id from the clone) and stops on local
  changes, so a pin bump needs no `--update`.
  `zmk-west.sh update` takes the patches off first (west refuses to move a patched
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
| Images | `./scripts/build-zmk.sh <targets> [--logging]` | `images:` lines `firmware/<name>.uf2  <12 hex>  FLASH … RAM …`, then `revisions: zmk …, zmk-keyboards …, zmk-beacon <hash> (pin), zmk-lantern <hash> (pin)` (a `--module` tree: `<dir> @ <describe> (--module)`) |
| Flash any one device on USB, no double-tap | `./scripts/flash-dongle.sh <prospector \| imprint_dongle \| imprint_left \| imprint_right \| image.uf2>` (`--dry-run` checks only, `--wait N` for a dongle a KVM switch hid, `--reset` for `*_RESET*`; a half only over a data cable while USB powers it, both halves may stay plugged in) | last line `[HH:MM:SS] DONE <device> serial=… <image> sha256=<the build summary's 12 hex>`, exit 0; then the display, both halves typing, or the flashed half typing and lit (re-enumeration does not show which image booted). `TIMES` counts each field from the 1200 baud touch; the Imprint Dongle's phases took mount 2.2-2.6 s, copy 9.5-12.2 s, re-enumeration 0.7-1.3 s (2026-09-27, t-eray, #222); a half's: mount 2.6-2.9 s, volume gone 4.0-4.3 s (an unchanged image), back with its port 5.0-5.3 s (2026-10-19, t-y6dz, two runs per half) |
| Flash the halves and the Imprint Dongle by double-tap (the first image with the 1200 baud entry, a `_RESET` flow, a failed run) | `./scripts/flash-watch.sh` or `./scripts/flash-reset.sh` (`--yes` skips the prompt), then double-tap one device at a time, the left half before the right (the mount order decides which is which); after a reset build, the order of [docs/recovery.md](docs/recovery.md) B (from source, not yet run on hardware) | `[HH:MM:SS] ALL DONE: left + right + dongle` (flash-reset.sh adds ` (NVS wiped)`), exit 0 |
| Find canon's devices | `python3 scripts/dongle.py list` | each of the four targets with its `/dev/cu.*` port, `location=… serial=…`, `port free` (a half by its stamp: the right half's product string is empty); `/Volumes/XIAO-SENSE  not mounted`; `flashers  none running` |
| Is the firmware on USB what origin/main builds? | `python3 scripts/dongle.py check [--json]` (after `git fetch`; opens no port) | one line per device and absent target: `imprint_dongle  current  stamp=<12 hex>  main=<12 hex>  serial=…  product="Imprint Dongle"`; exit 0 when every device is `current` (absent targets count as fine), 1 for `behind` (`since=<commits>`), `off-main`, `debug` (`inputs=current\|behind\|off-main`), `unstamped`; 3 when the digests could not be computed |
| See the Prospector Dongle's screen, dark or lit | `python3 scripts/dongle.py shot --out <scratch>/shot.png` (never inside a git work tree; refuses while a log reader holds the port), then Read the PNG | stdout the PNG's path, stderr `dongle.py shot: 280x240 in N bands, CRC-32 ok, …` |
| Set or ask the halves' LED colour (the palette) | `python3 scripts/dongle.py palette [RRGGBB …]` (one to four colours = slots 0…, none = ask; refuses while a log reader holds the port; no Imprint Dongle on USB = exit 1, no retry) | stdout `palette ok RRGGBB RRGGBB RRGGBB RRGGBB` (set) or `palette RRGGBB …` / `palette none` (ask), exit 0; both lit halves show slot 0 within a tick; a logging image: `slots 0-1 … stored` and `slot 0 … applied: hue H sat S brt B` on a half, `N colour(s) from …` and `resent to half N` on the dongle |

- An unchanged image copies in about 3 s, not 24 s (Prospector Dongle, bootloader 0.6.1, 2026-09-26:
  it skips matching pages, `src/flash_nrf5x.c`, and finishes only once every block has arrived,
  `src/usb/msc_uf2.c`): not a truncated copy.
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
  zephyr and every module (build-zmk.sh builds in its workspace copy). Besides ZMK it lists three
  modules (zmk-keyboards' imported manifest adds `zmk-pmw3610-driver`):
  - **Cyboard `zmk-keyboards` at branch `zephyr-4.1`, never `main`**: since 2026-07-07 `main` pins ZMK
    `v0.3.0` with the HWv1 `assimilator-bt` (`boards/arm/`), which fails against zmk@main with
    `Kconfig/soc/Kconfig.defconfig not found` on the two assimilator-bt targets (a partial red, first
    in CI on 2026-07-11, while canon's then-local `imprint_dongle` shield stayed green). The HWv2
    board is on `zephyr-4.1`, as Cyboard's own west.yml says; kept 2026-07-30 (t-wz4k).
  - **Own `zmk-beacon`, pinned by commit SHA** so that canon takes a change without a zmk-beacon
    release (2026-09-26, t-5gxp): the `prospector` shield and the Imprint Dongle's status
    broadcaster (payload: its `src/status_payload.h`). Bump the SHA by hand after a merge there.
  - **Own `zmk-lantern`, pinned by commit SHA the same way** (2026-10-19, t-26y4): the halves' key
    LEDs, lit only while USB powers the half and it is in use, and the boot light; the LED rail is
    its (the invariant below); and their colour, the palette (the glossary; t-k9e9): four colours
    `python3 scripts/dongle.py palette RRGGBB…` hands the Imprint Dongle as a line on its CDC ACM
    port (`palette` alone asks; the dongle answers `palette ok …`, `palette …`, `palette none` or
    `palette error: …`). The dongle stores them in NVS (`lantern/palette/colours`) and forwards them
    to both halves through the behavior node `palette` of `config/imprint_behaviors.dtsi`: ZMK's
    split transport names a behavior by its node name, so the node is the same on all three imprint
    targets, and the dongle builds the module's palette side (the Prospector Dongle none of the
    module). Each half stores the four and paints its LEDs with slot 0's hue and saturation at the
    conf's brightness, at arrival and at every boot (its settings commit runs after ZMK restored
    `rgb/underglow/state`); the dongle resends the palette a second after each battery report of a
    half, the first of which follows every reconnection (ZMK 4dd95d78 raises no central-side
    connection event), so a half that was away gets it when it is back; a half writes NVS only for
    a changed palette. Slots 1-3 change nothing until t-6ttk. The dongle's `palette ok` says it
    stored and queued, not that a half has it. Bump the SHA by hand after a merge there. The
    scripts treat every project of west.yml's `akira-toriyama` remote alike (`stamp.py pins`;
    t-66ww, 2026-10-19): the stamp takes its tree id, every build checks its clone out at the pin,
    and `build-zmk.sh --module <dir>` builds a local tree of it, so a third module needs no script
    change, only its project written like these two (`- name:` first, `remote: akira-toriyama`,
    `revision:` a full commit SHA: a branch or tag fails `stamp.py pins`, and the build; the
    glossary: own module).
- **ZMK tracks `main`, never a tag**, against ZMK's advice: the HWv2 `assimilator-bt` needs Zephyr's
  new hardware model; `v0.3.0` failed in `arch.cmake`: `Could not find ARCH=cyboard` (2026-05-17).
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
- **The USB product string `Imprint Dongle` is a contract**: chord's `VKeyHIDSource` finds the dongle
  by it, and flash-dongle.sh / dongle.py (`DEVICES`) by it when the device or image carries no
  firmware stamp (the stamp names the target first, 2026-10-19), as VID/PID `0x1D50`/`0x615E` are ZMK's defaults
  on all three dongles (the Imprint and ist dongles on one Mac, 2026-09-24; the Prospector Dongle's
  shield sets only the product string). It comes from the upstream shield's `ZMK_KEYBOARD_NAME`:
  never set `CONFIG_ZMK_KEYBOARD_NAME` for it in `config/`; an upstream rename changes chord's
  `productName` and `DEVICES` in `scripts/dongle.py` at once.
- **The USB manufacturer string is the firmware stamp, `ZMK Project (canon <shield> <12 hex><variant>)`**
  (`scripts/stamp.py`, the glossary): a digest of what this repository feeds that target's build,
  by content (`build.yaml`, `config/west.yml`, `scripts/zmk-west.sh`, every `patches/*/*.patch`,
  the `config/` files ZMK's candidate rule reads for the shield and board plus their includes,
  and the tree id of each own module's pin in place of its SHA), upstream left out; `<variant>` is
  the image suffix without its leading `-sprite`. The manifests of #263 to #266 (zmk-lantern's
  first) hashed its SHA as text: a device flashed from them reads `off-main` since t-66ww, until
  it is flashed again. Comments and blank runs drop out of `config/`,
  `build.yaml`, `west.yml` and `zmk-west.sh` (except Kconfig's `# CONFIG_X is not set`), so a
  comment-only change to `config/` keeps every stamp (#248); a patch is hashed as it applies and
  zmk-west.sh's messages count, so #242 moved them, and a pin bump moves all four targets, the
  halves included. Never set `CONFIG_USB_DEVICE_MANUFACTURER` in `config/`, keep the string under
  126 characters (a USB string descriptor's bLength), and never `--tag sprite`. `dongle.py check`
  reads it with `kUSBVendorString` (never "USB Vendor Name") and compares it with `origin/main`
  through the work tree's `stamp.py` (bumping its `ALGORITHM` turns every flashed device
  `off-main` until it is flashed again); its lines and `--json` are the contract with the daily
  check in dotfiles (t-ajkz). macOS's keyboard type is keyed on VID, PID and country code, not the
  manufacturer, and chord matches the product string: the stamp changes neither (Imprint Dongle,
  2026-10-13). The halves carry it too: plugged in to charge, they show it the same way
  (the right half on 2026-10-19: it enumerates without a product string, and stamped it is reported
  with its target; unstamped it would be reported without one).
- **Cyboard's `ZMK_RGB_UNDERGLOW` default `y` reaches every target**: zmk-keyboards'
  `boards/shields/imprint/Kconfig.defconfig` sets it outside any `SHIELD_` guard, so a target
  without a `zmk,underglow` chosen node fails with `#error` in `rgb_underglow.c` (2026-09-25).
  `config/imprint.conf` sets `CONFIG_ZMK_RGB_UNDERGLOW=n` for the Imprint Dongle and
  `config/prospector.conf` for the Prospector Dongle; the halves' confs, merged after `imprint.conf`,
  set it back to `y` for zmk-lantern (2026-10-19).
- **The halves' LED rail (assimilator-bt P1.02) is zmk-lantern's, never ZMK's `ext_power` driver's**:
  `config/lantern_rail.dtsi` (both halves' overlays) keeps the board's `EXT_POWER` node disabled,
  holds the pin low with a hog until the module takes it, and declares the `lantern,rail` node;
  `imprint_left.conf` / `imprint_right.conf` carry the five underglow lines the module asserts
  (`CONFIG_ZMK_RGB_UNDERGLOW=y`, `_EXT_POWER=n`, `_AUTO_OFF_USB=n`, `_AUTO_OFF_IDLE=n`, `_ON_START=n`;
  a wrong line is a build error) and `CONFIG_ZMK_IDLE_TIMEOUT=300000`, the module's idle rule
  (`CONFIG_LANTERN_OFF_WHEN_IDLE`, its default): five minutes without a key, sensor or pointing
  input on a half, and its LEDs go dark on USB too, lit again at the next input; each half counts
  for itself, and a cable plugged into an idle half lights nothing until its next key (the module's
  source says why). The timeout is ZMK's, not the module's (ZMK's activity state already counts
  the inputs, and t-6ttk's effects read the same); with `CONFIG_ZMK_SLEEP=n` it moves nothing
  else in a half but the battery sampling, paused while idle (the half's zmk.map, 2026-10-19).
  Never re-enable the node: the driver turns the rail on at init and
  restores a stored `ext_power/state/EXT_POWER` at settings load, and the left half's NVS holds off
  (the stock keymap's `&ext_power EP_OFF`), which kept it dark while the right half lit (t-y4ec,
  2026-10-19); erasing it is a settings reset, bonds included. No `&ext_power` or `&rgb_ug` key:
  through the dongle a press never reaches the halves, and an `&rgb_ug` on battery would run the
  strip with the rail off (zmk-lantern's README). On battery the rail is off, as since #207 (10-18 mA
  per half at rest with it on, 0.79 mA off; 2026-09-15). A half that boots on battery within a minute
  of a plugged spell shows ZMK's saved colour for about 0.1 s first: by design, not a fault.
  On hardware 2026-10-19 (t-26y4, both halves): the boot light on battery, then dark; lit on plugging
  in and dark on unplugging, per half; lit through a boot on USB.
- **The Imprint Dongle builds with `CONFIG_BT_EXT_ADV` and needs `CONFIG_BT_EXT_ADV_MAX_ADV_SET=2`**
  (`config/imprint_dongle.conf`): `CONFIG_BEACON_STATUS_BROADCAST` selects it for a second
  advertising set, and the host serves ZMK's legacy `bt_le_adv_start()` from the same pool; a pool
  of 1 fails zmk-beacon's `BUILD_ASSERT`. Costs: about 34 KB flash and 11 KB RAM, the host on
  extended HCI commands, and an extended scan following nearby AuxPtr fields, where ZMK's Zephyr
  fork lacks upstream 5ce9d0c621 (an assert on an invalid `chan_idx`; if it bites, carry it in
  `patches/zephyr/`). Hardware 2026-09-26/27 (t-eray): reconnects unchanged over 5 reboots and a
  half's power cycle, 0 advertising errors, 255-269 payloads a minute.
- **Both dongles mount the same `XIAO-SENSE` bootloader volume, and flash-watch.sh / flash-reset.sh
  copy `imprint_dongle*.uf2` onto the first XIAO bootloader they see and the halves' images onto any
  other**: never put the Prospector Dongle into its bootloader while they run, nor both dongles at
  once. flash-dongle.sh guards this (their shared lock; no start while any UF2 volume is mounted; a
  copy only onto the volume whose disk sits at that device's USB location, which its bootloader
  keeps (the XIAOs 2026-09-26, the halves 2026-10-19), never onto a volume by name: both halves mount
  as `ASSIMILATOR` (Adafruit UF2 bootloader 0.9.2); details: its header). The
  first image with the 1200 baud entry, or a failed run, takes a double-tap + `cp -X` (README,
  docs/recovery.md).
- **A canon device's port rate is a command**: 1200 baud reboots either dongle or either half into
  its UF2 bootloader (the halves seen 2026-10-19, t-y6dz), 2400 makes the Prospector Dongle send its screen (zmk-beacon's
  `CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD`, on in its shield, since 2026-09-27 in
  `config/imprint_dongle.conf`, whose product image has the port too, and since 2026-10-19 in
  `config/imprint_left.conf` / `imprint_right.conf` with the port from `config/cdc_acm_port.dtsi`;
  `CONFIG_BEACON_SCREEN_DUMP`). Any program that sets the rate does it (`stty`, a serial monitor):
  never open a canon device's port at either rate by hand. A line `palette …` on the Imprint
  Dongle's port at 115200 is a command too (zmk-lantern's `CONFIG_LANTERN_PALETTE_PORT`): only
  `dongle.py palette` sends it, and it refuses while a log reader holds the port, which would take
  the reply. Find ports by the firmware stamp or a
  dongle's USB product string, never by VID/PID or a `/dev/cu.usbmodem*` name (it follows the USB
  location). The option depends on `USB_CDC_ACM`, without which `=y` drops out with a mere warning:
  after a ZMK bump, grep it in `build/<shield>/zephyr/.config` of the Imprint Dongle and both halves.
- **A split peripheral's slot index is the order the dongle first hears it, persisted**: ZMK's
  `zmk_ble_put_peripheral_addr()` (`app/src/ble.c`) saves a new advertiser in the first free slot,
  before pairing and even if pairing fails, and `reserve_peripheral_slot()` (`central.c`) maps it back
  until the Imprint Dongle's NVS reset (read 2026-10-04, ZMK 5b51501f). Consumers: chord's split
  battery `source` and zmk-beacon's `src/status_broadcaster.c` (slot 0 → the left byte). Slot 0 is the
  left half (2026-09-27, t-eray); after a reset, the left half pairs first (docs/recovery.md B).
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
  Never put a GIF or anything made of one (sprite packs, frames, C arrays, previews, `shot` PNGs)
  into a commit, PR, issue, CI or release, nor its subject, file name or sprite name into their
  text or a doc.
- Local only: `./scripts/build-zmk.sh prospector --sprite <gif>` writes
  `firmware/prospector-sprite.uf2` (zmk-beacon's `CONFIG_BEACON_SPRITE_GIF`): the configure step
  converts the GIF into a sprite pack (zmk-beacon's `tools/sprite_pack.py`, format and reasons in
  its `docs/sprite-pack.md`; since zmk-beacon fe32b13, t-4dsj) and embeds the pack, never the GIF.
  The player keeps the canvas and picture 0 in the LVGL pool, which zmk-beacon's shield sizes at
  64 KiB with a sprite (48 KiB without; `config/prospector.conf` never sets it), and CMake stops a
  GIF that does not fit, naming the pool size that would. The CI and release
  `prospector.uf2` carries neither sprite nor name, but flashing it removes neither: the sprite
  room survives a flash and its pack plays at boot (zmk-beacon's README; seen 2026-10-13 after
  flash-dongle.sh put the pinned image on). The GIFs and
  `SOURCES.md` live off the repository on the user's external drive,
  `/Volumes/HDD/assets/canon/prospector/sprites/` (`shot` PNGs: `.../prospector/shots/`), the same
  absolute path from any checkout or worktree ([assets/README.md](assets/README.md); t-kbjr). The
  drive is exFAT: copy onto it with `cp -X`, and give `--sprite` one file, never a `*.gif` glob,
  which also matches macOS's `._` sidecar files. `assets/`'s ignore rules stay as a guard.
- [assets/sprite-name.sh](assets/sprite-name.sh) derives the name from the file name (t-er81);
  build-zmk.sh passes it as `CONFIG_BEACON_SPRITE_NAME` in a Kconfig fragment
  (`cfgrepo/.sprite/sprite.conf`, `EXTRA_CONF_FILE`), never `-DCONFIG_...`, which west prints when
  the configure step fails (reproduced 2026-09-29), and prints only the GIF's size and the name's
  length. `cfgrepo/.sprite/` and a sprite build's directory (`zephyr/.config`, the image,
  `modules/zmk-beacon/beacon_sprite.spk` and `beacon_sprite_pack.inc`) hold the GIF, the pack and
  the name: never print or paste from them. The screen layout (zmk-beacon's README, the
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
  paid API; Claude reviews run locally. The main ruleset requires `lint / lint` and all four
  builds (prospector's since 2026-10-04): a new build.yaml target joins it.
- Fleet-managed, never edited here (fleet-sync in akira-toriyama/.github overwrites them):
  `.github/workflows/{actionlint,commit-lint,repo-policy,taplo,task-status,version-preview,zizmor}.yml`,
  `.github/zizmor.yml`, `.github/dependabot.yml`, `docs/commit-convention.md`. `glyph.toml` came
  from `glyph init --gemoji --v1-window` and carries a hand edit (#197): edit it, never regenerate it.
