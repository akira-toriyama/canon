# Recovery

Pairing recovery between the Cyboard Imprint's halves and the Imprint Dongle
(their split central), and the bring-up of a new set. `flash-watch.sh` and
`flash-reset.sh` read `firmware/` of the checkout they live in; the user's
images are in the main checkout, `/Volumes/workspace/github.com/akira-toriyama/canon`.

## Pairing recovery

### Ground rules

- Each device keeps its bonds in its settings (NVS), and the Imprint Dongle
  also its two peripheral slots ([Slot order](#slot-order)). Reset taps, USB
  replugs, power cycles and flashes of a normal image keep them. They go only
  through a settings-erasing image (canon's `*_RESET.uf2`, or Cyboard's
  `settings_reset.uf2` on a half) and, one bond at a time on the Imprint
  Dongle, through [auto-recovery](#auto-recovery-and-what-was-rejected).
- A `*_RESET.uf2` is the normal build plus `CONFIG_ZMK_SETTINGS_RESET_ON_START=y`
  ([build-zmk.sh](../scripts/build-zmk.sh) `--reset`): it erases at every boot,
  before Bluetooth starts, until a normal image replaces it.
- The halves reach their bootloader only by a reset double-tap; a single tap
  reboots. No key in the keymap uses the `&bt` or `&bootloader` behavior.
- The Cyboard Imprint may be the Mac's only keyboard. Nothing types from an
  erase until the halves pair again: have another USB keyboard or the macOS
  Accessibility Keyboard ready first.

### Triage

`python3 scripts/dongle.py list` (ioreg, lsof and pgrep; it opens no port):

- `imprint_dongle … absent`: the Imprint Dongle is not on this Mac's USB (a
  KVM switch hides both dongles; cable, hub). Not a pairing fault.
- A `UF2 bootloader on` line: a device sits in its bootloader (a double-tap or
  a failed `flash-dongle.sh` run). Finish that flash first.
- `flashers` naming a process: `flash-impl.sh`, the body of `flash-watch.sh`
  and `flash-reset.sh` (a `_RESET` argument marks the latter), still waits for
  double-taps.
- An interrupted B leaves devices on a `*_RESET.uf2`: run B again from step 2.

Then A; if a half stays silent, B.

### A. Re-plug the Imprint Dongle

No computer needed.

1. Unplug the Imprint Dongle.
2. Power both halves on and wait 10 s.
3. Plug the Imprint Dongle back in.
4. Wait 30-60 s without touching anything.
5. Press a key on each half. If one stays silent, B (or the one-half erase in
   [Why bonds break](#why-bonds-break)).

Re-plugging reboots the dongle; bonds and slots stay. A brought the Cyboard
Imprint back once, on 2026-06-19 (98a05c5), after a test of the `*_RESET.uf2`
flow had left the halves unable to re-pair; 98a05c5 records neither that
test's flash order nor whether the `*_RESET.uf2` images were still on the
devices when A was done. By the analysis under B, A on normal images cannot
clear a bond that a half holds and the dongle lacks.

### B. Erase all three and re-pair

For the bonds A cannot fix ([Why bonds break](#why-bonds-break)).

1. `./scripts/build-zmk.sh imprint --reset` writes
   `firmware/imprint_{left,right,dongle}_RESET.uf2`, `./scripts/build-zmk.sh imprint`
   the normal three (Docker must run). Skip when both sets are current.
2. Power the right half off and keep its USB cable out until its turn in
   step 3; keep any other unbonded ZMK split peripheral (a half of another set
   being erased, say) off until step 3 ends.
3. `./scripts/flash-reset.sh`, then double-tap one device at a time, each
   after the previous one's `DONE` line: the Imprint Dongle, the left half, the
   right half. It ends with `ALL DONE: left + right + dongle (NVS wiped)`.
4. `./scripts/flash-watch.sh`, same order, ending with
   `ALL DONE: left + right + dongle`.
5. Press a key on each half, then check the [slot order](#slot-order).

Steps 3 and 4 as one paste, after A, with step 2 done and double-tapping in
step 3's order (`--yes`, or running without a TTY, skips the Enter prompt).
Only when all six images are in the main checkout's `firmware/`
(`ls firmware/imprint_{left,right,dongle}{,_RESET}.uf2` there lists them
without an error): the scripts look for an image only once its device has
mounted, so a missing one leaves that device in its bootloader:

```sh
cd /Volumes/workspace/github.com/akira-toriyama/canon && ./scripts/flash-reset.sh --yes && ./scripts/flash-watch.sh --yes
```

Steps 1, 3 and 4, rebuilding first:

```sh
cd /Volumes/workspace/github.com/akira-toriyama/canon && ./scripts/build-zmk.sh imprint --reset && ./scripts/build-zmk.sh imprint && ./scripts/flash-reset.sh --yes && ./scripts/flash-watch.sh --yes
```

A pasted line still needs Return: zsh's bracketed paste (`zle_bracketed_paste`
in zshparam(1), on by default since zsh 5.1) inserts a pasted newline instead
of running the line.

The order comes from source (ZMK 5b51501f, which is ZMK main on 2026-10-04,
and its Zephyr v4.1.0+zmk-fixes 10ba6d0, checked again by an independent
reading the same day) and has not yet been run on hardware:

- A `*_RESET.uf2` runs the whole firmware, Bluetooth included, after its
  boot-time erase, so devices pair while running it, and the normal image,
  which never erases, keeps those bonds. ZMK's own `settings_reset` shield
  turns Bluetooth off (`CONFIG_ZMK_BLE=n`, "so splits don't try to re-pair until
  normal firmware is flashed"), but on assimilator-bt, in place of
  `imprint_left` / `imprint_right`, it fails in cmake with
  `undefined node label 'spi1_default'` (58ef3bc, 2026-06-19): the board
  references pin states that only the imprint shield's overlay defines.
- The Imprint Dongle first: a half erased while the dongle still holds its old
  bond pairs with it again at once (auto-recovery), and an erase of the dongle
  after that leaves the half with a bond the dongle lacks, the state B exists
  to clear. Erased first, the dongle pairs each half after that half's erase.
- The right half off: the first split peripheral the erased dongle hears
  takes slot 0.
- The Imprint Dongle must not boot between its two images: a single tap
  instead of a double-tap, a replug or a power loss boots its `*_RESET.uf2`,
  which erases it after the halves paired. Then B again from step 2. The same
  on a half is repaired by auto-recovery.

What the scripts do ([flash-impl.sh](../scripts/flash-impl.sh)):

- A UF2 volume whose `INFO_UF2.TXT` names XIAO gets `imprint_dongle[_RESET].uf2`;
  any other is taken for the left half, the next for the right half. Each pass
  takes the first such volume under `/Volumes`, hence one device in its
  bootloader at a time.
- Nothing else may enter a UF2 bootloader while they run: a XIAO (the
  Prospector Dongle, the ist dongle of zmk-hid-host) would get
  `imprint_dongle*.uf2`, any other board (zmk-hid-host's Feather RP2040, for
  one) would be taken for a half.
- They hold the lock `flash-dongle.sh` takes, and `flash-dongle.sh` also
  refuses while they run, so in B the Imprint Dongle goes by double-tap like the
  halves.

### Slot order

- The Imprint Dongle has two peripheral slots (`CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS=2`,
  upstream `imprint_dongle` shield) and two bonds (`CONFIG_BT_MAX_PAIRED=2` in
  [config/imprint_dongle.conf](../config/imprint_dongle.conf), both for the
  halves; the Mac is on USB). With its settings erased, the first split
  peripheral it hears, by undirected or directed advertising, takes slot 0 and
  the next slot 1, saved at once as `ble/peripheral_addresses/<i>` (ZMK
  `app/src/ble.c` `zmk_ble_put_peripheral_addr()`), before any pairing and
  even if the pairing then fails. The index then follows the half's address
  through every reconnect and reboot until the Imprint Dongle's settings are
  erased. A half's own erase keeps its slot: its address is the chip's static
  address (FICR; Zephyr `bt_setup_random_id_addr()`, `CONFIG_BT_PRIVACY` off),
  not a setting (derived from source).
- Slot 0 must be the left half: the split battery report's `source`, which
  chord passes on as `CHORD_BATTERY_SOURCE` (its README's example maps 0 to
  left), and the left byte of the status advertisement (zmk-beacon
  `src/status_broadcaster.c`) read it so. The current bonds have it
  (2026-09-27, each half powered off in turn; projects t-eray). The Prospector
  Dongle's HP bar shows the mean of both halves, so a swap does not show there.
- Check: switch the left half off with its USB cable out; chord's log
  (`/tmp/chord.log`, `vkey-hid: battery source=<slot> …`) shows a level 0 for
  `source=0`. Swapped: B again.

### Why bonds break

From the same source:

- A half with a bond advertises directed at its dongle's address only; one
  without a bond advertises the split service to any central
  (`app/src/split/bluetooth/peripheral.c`). The Imprint Dongle connects to both
  kinds (`central.c`). The split service's characteristics need encryption, so
  every connection then encrypts with the stored bond or pairs.
- The dongle holds a bond the half lost (the half was erased): its encryption
  fails with `BT_SECURITY_ERR_PIN_OR_KEY_MISSING` (err 2). Auto-recovery repairs
  it.
- The half holds a bond the dongle lost (the dongle was erased, alone or after
  the halves): the half refuses the dongle's Just Works pairing (Zephyr
  `subsys/bluetooth/host/smp.c` `update_keys_check()`;
  `CONFIG_BT_SMP_ALLOW_UNAUTH_OVERWRITE` is off, ZMK implies it only with
  `ZMK_BLE_EXPERIMENTAL_SEC`), the dongle gets err 4
  (`BT_SECURITY_ERR_AUTH_REQUIREMENT`), and the half stays silent. Only erasing
  the half helps. When one half alone is silent and the slot order is right,
  erasing that half by hand is enough: double-tap it, `cp -X` its
  `*_RESET.uf2`, let it pair, double-tap, `cp -X` its normal image
  (`flash-reset.sh` would take whichever half mounts first for the left).
  Otherwise B.
- Both slots hold other addresses (a replaced half, a dongle from another set):
  the dongle never connects the new half. B.
- A reboot reloads the same bonds, so repeated resets change nothing.

To tell them apart, build a logging Imprint Dongle
(`./scripts/build-zmk.sh imprint_dongle --logging`, flashed with
`./scripts/flash-dongle.sh firmware/imprint_dongle-logging.uf2`), start
`python3 scripts/dongle.py log imprint_dongle --seconds 90 --grep '(?i)security failed|stale bond|reserve'`
and then, while it runs, replug the Imprint Dongle (the reader follows it
through the reboot) or switch the silent half off and on, USB cable out: these
lines come when the dongle boots or a half connects, all three at the logging
build's INFO level.

- `Security failed: … err 2` followed by
  `Stale bond detected, clearing and disconnecting`: auto-recovery at work.
- `err 4` at each connection: the refused pairing.
- `Unable to reserve peripheral slot (err -12)`: an advertiser whose address
  is in neither slot while both are taken (an outsider: a replaced half, or
  any unbonded ZMK split peripheral in range), or a half whose slot still
  holds its old connection (a stale -12: until the 4 s supervision timeout
  drops it, and only while the other half is not connected, as the dongle
  scans only then). The line names no address, and the dongle reports an
  advertiser once per scan (a duplicate filter), so the count of the lines is
  no guide. A stale -12 can leave that half silent, through its own off and
  on, until the dongle starts a new scan: a replug (A) or the other half
  connecting.
  - To tell them apart, start a new scan with the log running: replug the
    Imprint Dongle (A; the INFO `--logging` image's ring keeps the boot log)
    or switch a connected half off, USB cable out, for more than 4 s and on.
    Neither can make a stale -12 (a reboot drops every old connection, and
    the timeout drops that of a half away longer than 4 s), so a -12 then is
    an outsider's; none means no outsider is advertising now.
  - The DEBUG image (CLAUDE.md, Debugging:
    `firmware/imprint_dongle-logging-kconfig.uf2`), read with
    `--grep '(?i)slot'`, adds the slot addresses: an outsider's -12 comes
    right after `peripheral slot 0 occupied by <addr>` and
    `peripheral slot 1 occupied by <addr>`. With it, start the scan by
    switching a connected half off and on as above, not by a replug: a DEBUG
    boot overflows the log buffer and the ring. Flash the product image back afterwards
    (`./scripts/flash-dongle.sh imprint_dongle`): DEBUG logs keycodes.

  Derived from source (ZMK 5b51501f, Zephyr 10ba6d0), not run on hardware.

### Auto-recovery and what was rejected

- [patches/zmk/security-changed-auto-unpair.patch](../patches/zmk/security-changed-auto-unpair.patch):
  on `BT_SECURITY_ERR_PIN_OR_KEY_MISSING`, ZMK `app/src/ble.c`
  `security_changed()` unpairs the peer and disconnects; the next connection
  pairs fresh in the same slot. `scripts/zmk-west.sh patch` applies it to every
  build (build-zmk.sh, and zmk-build.yml for CI and the release) with no Kconfig
  gate. ZMK builds `ble.c` only for a split central or a non-split keyboard, so
  only the Imprint Dongle runs it. Upstream: zmkfirmware/zmk#3385 (open), gated
  there by `CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISSING`, which canon does not
  have ([patches/zmk/README.md](../patches/zmk/README.md)).
- `&bt BT_CLR`, rejected: `zmk_ble_clear_bonds()` clears the active BLE host
  profile's bond, never a split bond, and the Imprint Dongle has no host profile
  (`ZMK_BLE_PROFILE_COUNT` = `CONFIG_BT_MAX_PAIRED` 2 - 2 peripherals = 0), so it
  would index the zero-length `profiles[]`. `behavior_bt.c` builds only for the
  split central, the Imprint Dongle, which a half's key press reaches only over
  the BLE link that failed.

### The dongles on their own

- `./scripts/flash-dongle.sh imprint_dongle` reflashes the Imprint Dongle with
  `firmware/imprint_dongle.uf2` through its 1200 baud bootloader entry
  (`CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD` in `config/imprint_dongle.conf`, in
  every Imprint Dongle image built since 2026-09-27, `*_RESET.uf2` included),
  without a double-tap; bonds stay. It refuses while `flash-watch.sh` /
  `flash-reset.sh` run or `/Volumes/XIAO-SENSE` is mounted. By hand (an image
  without the entry on the device, or a failed run): double-tap, then
  `cp -X firmware/imprint_dongle.uf2 /Volumes/XIAO-SENSE/`; nothing types until
  it is done.
- `./scripts/flash-dongle.sh --reset firmware/imprint_dongle_RESET.uf2` erases
  the Imprint Dongle alone, which leaves the halves with bonds it lacks:
  re-pairing all three is B.
- The Prospector Dongle holds no bonds (zmk-beacon's shield sets
  `CONFIG_ZMK_BLE=n`; it only observes the status advertisement) and needs no
  recovery step. Its bootloader also mounts as `XIAO-SENSE`: never double-tap
  it or open its port at 1200 baud while `flash-watch.sh` / `flash-reset.sh`
  run, and finish or unplug one that a failed `flash-dongle.sh` run left in its
  bootloader before they start.

## New-unit provisioning

Steps 1-3 and step 5's flash and enumeration were verified on 2026-08-04 by
bringing up a second Cyboard Imprint and Imprint Dongle on a Mac without
Docker, from release files only (copied with plain `cp`, which warned about
extended attributes; `cp -X` is the practice since 2026-09-24, 328dffc). Step
4, step 5's typing check and step 6 (the left half pairs first) follow the
[slot order](#slot-order) rule and have not been run on hardware; on 2026-08-04
the pairing used A's order (halves first, dongle last), before the split
battery report (2026-09-24) gave the slot order a reader. With Docker, B erases
all three instead, with images that keep Bluetooth on, hence its order.

1. canon's images: `gh release download <tag> --repo akira-toriyama/canon -p '*.uf2' -D firmware`.
   A draft works for an authenticated owner (the v3.0.0 draft on 2026-10-04:
   `imprint_left.uf2`, `imprint_right.uf2`, `imprint_dongle.uf2`,
   `prospector.uf2`); [release.yml](../.github/workflows/release.yml) rebuilds
   the rolling draft's images on pushes to main.
2. Cyboard's files: the releases of
   [Cyboard-DigitalTailor/cyboard-imprint-zmk-studio-firmware](https://github.com/Cyboard-DigitalTailor/cyboard-imprint-zmk-studio-firmware)
   carry `settings_reset.uf2` (erases a half's settings), `imprint_left-studio.uf2`
   and `imprint_right.uf2` (checked on imprint-v2026.09.27, 2026-10-04).
   Cyboard's left and right make a self-contained hardware test: there the left
   half is the central, and the left over USB and the right over BLE must both
   type.
3. Each half, one at a time: double-tap, `cp -X settings_reset.uf2` onto the
   volume that mounts, let it run 15 s or more, double-tap, copy canon's image
   for that half. Verify the boot by USB enumeration (both halves enumerated on
   2026-08-04): the left half's USB product string is `Imprint`, the right
   half's is empty (zmk-keyboards names only `imprint_left`;
   `CONFIG_USB_DEVICE_PRODUCT=""` in canon's right-half build). Neither types
   over USB: ZMK's USB HID needs the central role. Tell the units apart by USB
   serial number.
4. Power the right half off and unplug it, so that the left half pairs first.
5. Imprint Dongle: double-tap, `cp -X firmware/imprint_dongle.uf2 /Volumes/XIAO-SENSE/`.
   It must enumerate as `Imprint Dongle` (a HID keyboard, usage page 1 /
   usage 6), and the left half must type through it. Later flashes go through
   `./scripts/flash-dongle.sh imprint_dongle`.
6. Power the right half on; it must type too.

Learned in that bring-up:

- A ~400 KB image whose copy took 7-9 s and warned only about extended
  attributes booted; three copies of 1-3 s that failed on the data with
  `fcopyfile … Input/output error` / `Device not configured` left a device that
  never booted (mechanism inferred, not proven). Neither sign proves anything
  alone: on bootloader 0.6.1 an unchanged image copied in about 3 s against
  about 24 s for a new one (Prospector Dongle, 2026-09-26; pages that already
  match are skipped), and a good copy can end in that I/O error as the
  bootloader reboots. A `DONE` line is no proof either: verify the boot by USB
  enumeration.
- A half absent from USB twice in a row (replug, then a single tap) is not
  running its firmware: reflash before suspecting Bluetooth.
- A missed double-tap (a single tap reboots) looks like a missing bootloader;
  check twice before concluding.
- Halves that ran Cyboard's or factory firmware keep bonds in their settings;
  the sequence that worked erased them with `settings_reset.uf2` first (not
  isolated as the cause).
