# patches/zmk/

Out-of-tree patches to ZMK, the `zmk/` west project (zmkfirmware/zmk at
`main`, [config/west.yml](../../config/west.yml)). Every build applies them
with `scripts/zmk-west.sh patch`: [scripts/build-zmk.sh](../../scripts/build-zmk.sh)
locally, [.github/workflows/zmk-build.yml](../../.github/workflows/zmk-build.yml)
in CI. [patches/zephyr/](../zephyr/README.md) goes through the same loop. A
patch stays until upstream takes it. Not a ZMK fork: canon follows zmk@main,
which a fork would have to keep rebasing onto, while a patch that no longer
applies stops the next build.

## How the patches go on

- `patches/<tree>/*.patch` patches the west project at `<topdir>/<tree>`. The
  topdir is the CI checkout, or locally `$ZMK_WS/cfgrepo` (default
  `~/.cache/zmk-canon/cfgrepo`, `/workspace` inside the container). Trees go
  zmk first, then zephyr; within a tree, in `LC_ALL=C` file-name order.
- No tree is reset to pristine. `patch` checks each file on its own: one that
  reverse-applies is `(already applied)` and skipped, one that applies goes on
  the working tree (the index stays at HEAD), and one that does neither stops
  the build (`applies neither forward nor in reverse`); there is no silent skip.
- `update` (the first local build, `--update`, every CI job) first
  reverse-applies, last to first, each patch the working tree carries and the
  index does not, because `west update` refuses a revision that changes a
  patched file; then it runs `west update`. Update the workspace through it
  (`./scripts/build-zmk.sh --update`), never with a bare `west update`.
- On a fresh tree (CI), `(already applied)` means upstream now carries the
  change: delete the patch.
- A local build uses the zmk commit of its last `update`; CI takes zmk@main on
  every run.

## Adding or changing a patch

- A patch is a `git diff` against HEAD with every patch that sorts before it
  applied (git apply also takes a plain unified diff, which the zephyr patch
  is; write new ones with the steps below); name a new one so that `LC_ALL=C`
  order puts it after the patches it builds on.
- On a built tree every patch is applied and still has to reverse-apply on its
  own, so no patch may add, remove or change lines inside another patch's
  hunks (its added lines and their context).
- Edit in the workspace tree (`~/.cache/zmk-canon/cfgrepo/zmk` after a build:
  every patch applied and unstaged, created files untracked), then write the
  patch from it through a scratch index, which leaves the tree's own index at
  HEAD. `P` is absolute: `git -C` resolves a relative patch path against the
  tree.

  ```sh
  T=~/.cache/zmk-canon/cfgrepo/zmk
  P=/absolute/path/to/canon/patches/zmk
  export GIT_INDEX_FILE="$(mktemp -d)/index"
  git -C "$T" read-tree HEAD
  git -C "$T" apply --cached "$P"/<each patch that sorts before it>
  git -C "$T" add -N <files the patch creates>
  git -C "$T" diff -- <files the patch touches> > "$P/<name>.patch"
  unset GIT_INDEX_FILE
  ```

  When a later patch touches one of those files, `git -C "$T" apply --reverse`
  it first; the next build puts it back. On a scratch clone of zmk 5b51501f
  these steps reproduced vkey-report.patch hunk for hunk (2026-10-04).
- A patch that stops applying after zmk moved: `git -C "$T" apply --reject`
  applies the hunks that fit and writes the rest to `*.rej` files; fix those
  by hand, delete them, and regenerate as above.
- A patch file that changes any other way (a hand edit, a pull) leaves the
  workspace tree carrying its old version: the next local build stops at
  `patch`, and a deleted patch or a dropped hunk goes unnoticed, the tree
  keeping the removed change. After such a change, reset the tree unless it
  holds an edit you still need: `git -C ~/.cache/zmk-canon/cfgrepo/zmk
  checkout -- . && git -C ~/.cache/zmk-canon/cfgrepo/zmk clean -fd`, or
  delete the whole workspace with `./scripts/build-zmk.sh --clean`.
- Build a target that compiles it (`./scripts/build-zmk.sh imprint_dongle`);
  the PR's CI applies the whole set to a fresh tree. Add an entry below.

## The patches

Every build target builds against the patched tree; patched code compiles
only where ZMK compiles that file. Upstream state checked 2026-10-04.

### security-changed-auto-unpair.patch

`security_changed()` in `app/src/ble.c`: on
`BT_SECURITY_ERR_PIN_OR_KEY_MISSING` it calls `bt_unpair()` on the peer and
`bt_conn_disconnect()`, so the next connection pairs afresh. When a half has
lost its bond and the Imprint Dongle (split central) still holds it, every
reconnect otherwise fails the handshake with that error, and only wiping the
bonds on both sides ends the loop. The reverse case, a bond the dongle lost and
the half kept, is not this error and is not covered
([docs/recovery.md](../../docs/recovery.md)). No Kconfig gate: canon always
runs it. `ble.c` compiles only into non-split and split-central builds with
`ZMK_BLE`: the Imprint Dongle.

Upstream: [zmk#3385](https://github.com/zmkfirmware/zmk/pull/3385)
(`CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISSING`, default n), open; its
description links this file by name, so keep the name. The earlier
split-central-only variant, [zmk#3377](https://github.com/zmkfirmware/zmk/pull/3377)
(`CONFIG_ZMK_SPLIT_AUTO_UNPAIR_ON_KEY_MISMATCH`), is open too.

### split-battery-source-bounds.patch

A range check on `source` in the battery-event case of
`app/src/split/central.c`. Upstream checks it on the read side only
(`zmk_split_central_get_peripheral_battery_level()`); the write to
`peripheral_battery_levels[source]` is unchecked. The BLE transport's
`split_central_disconnected()` fills the event's `uint8_t source` from
`peripheral_slot_index_for_conn()`, which returns `-EINVAL` for a connection
that never held a peripheral slot, and unlike `split_central_connected()` it
has no `BT_CONN_ROLE_CENTRAL` filter: the disconnect of any such connection
writes 0 to index 234 of a 2-byte array. The case compiles only with
`CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING`, which canon turned on
in [config/imprint_dongle.conf](../../config/imprint_dongle.conf) in the same
change as this patch (2026-09-24): the Imprint Dongle.

Upstream: not submitted. An upstream bug fix of its own, independent of
zmk#3390.

### usb-hid-prime-on-ready.patch

A pending-report ring in `app/src/usb_hid.c`. Upstream
`zmk_usb_hid_send_report()` drops a report sent while the bus is not ready:
`USB_DC_SUSPEND` returns `usb_wakeup_request()`, `ERROR`, `RESET`,
`DISCONNECTED` and `UNKNOWN` return `-ENODEV`. The patch queues those reports
(and `CONNECTED` ones) and flushes them 100 ms after `USB_DC_CONFIGURED` or
`USB_DC_RESUME`; the delay also covers macOS seeming to drop the first report
from a freshly bound interface (seen while testing canon#43 and zmk#3384,
2026-06; 100 ms found enough by trial). Three symptoms went away with the
patch on hardware (canon#43, 2026-06-09), hence one inferred mechanism behind
them: the first key lost after replugging the dongle, the first key lost after
the host wakes, several presses needed after a long idle (the bus suspended
while the host idles).

- 8 slots of up to 16 bytes, so at most 7 reports wait; a full ring drops its
  oldest entry, and a report longer than 16 bytes is dropped, not queued
  (canon's keyboard and consumer reports are 9 and 13 bytes; NKRO's extended
  report would be 22). A physical disconnect empties the ring, so old
  keystrokes are not replayed on replug. A live report queues behind pending
  ones instead of overtaking them. The code comments and zmk#3384's
  description give the reasons per USB state (`CONNECTED`: a write on a bus
  not yet configured fails silently).
- `usb_hid.c` compiles only with `ZMK_USB`: the Imprint Dongle (a split
  peripheral cannot enable it, the Prospector Dongle turns it off).

Upstream: [zmk#3384](https://github.com/zmkfirmware/zmk/pull/3384)
(`CONFIG_ZMK_USB_HID_REPLAY_ON_READY`, default n, with
`CONFIG_ZMK_USB_HID_REPLAY_QUEUE_DEPTH` 8, `CONFIG_ZMK_USB_HID_REPLAY_REPORT_MAX_LEN`
16 and `CONFIG_ZMK_USB_HID_REPLAY_FLUSH_DELAY_MS` 100), open; its description links
this file by name, so keep the name. Related issue
[zmk#2686](https://github.com/zmkfirmware/zmk/issues/2686), open.

### vkey-report.patch

Adds the vkey and the split battery report (entries in
[docs/glossary.md](../../docs/glossary.md)), the two reports the host bridge
chord reads.

- Report `0x20`: the vkey selector, 1 byte (`1`–`255` the id, `0` released),
  in an independent Application collection on vendor usage page `0xFF31`
  (usage 0x01 the collection, 0x02 the selector), appended after every
  standard collection and outside the `CONFIG_ZMK_POINTING` guard. ZMK's own
  report IDs are 0x01 (keyboard, LEDs), 0x02 (consumer) and 0x03 (mouse).
- `&vkey <id>`: `app/src/behaviors/behavior_vkey.c` and binding
  `zmk,behavior-vkey` (node in
  [config/imprint_behaviors.dtsi](../../config/imprint_behaviors.dtsi)).
  Press sets the id and sends, release sends 0. It runs on the central and
  sets the report directly instead of raising a keycode event: ZMK's HID path
  (`zmk_hid_press()`) reports only the keyboard and consumer pages, and an
  encoded keycode keeps 8 bits of page, too few for 0xFF31.
  `zmk_endpoint_clear_reports()` clears
  and resends it too, so an endpoint switch cannot strand a held vkey.
- Report `0x21`, the split battery report: `{source, level}` in the same
  collection, from a listener on `zmk_peripheral_battery_state_changed`
  (`app/src/split/bluetooth/central_battery_hid.c`), under the new
  `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_HID` (inside
  `if ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING`, `depends on ZMK_USB`;
  both on in config/imprint_dongle.conf). What `source` and `level` mean: the
  glossary entry.
- chord (`Sources/ChordAdapterMacOS/VKeyHIDSource.swift`) reads
  `[0x20, selector]` and `[0x21, source, level]` from the USB device named
  `Imprint Dongle`. Changing a report ID or a report's byte layout is a wire
  change chord has to follow; chord does not check the usage page (it
  matches VID/PID and the product string).
- Of the C files it changes or adds, the Imprint Dongle compiles all, the
  halves none (central-only sources), and the Prospector Dongle, a non-split
  build, `hid.c` and `endpoints.c`. `behavior_vkey.c` is listed inside the
  central block of `app/CMakeLists.txt`: a split peripheral lacks the HID and
  endpoint functions it calls.

Decisions not to undo:

- A core patch, not a module: the report descriptor is core
  (`zmk_hid_report_desc[]` in `hid.h`, registered by `usb_hid.c` and served
  as the HOG report map by `hog.c`). A module cannot extend it and would have
  to add a second USB HID interface (the badjeff/zmk-hid-io approach), a
  different wire for chord.
- One patch. The 0x21 items sit inside the vkey collection: they use its
  Usage Page and close with its End Collection, which places them inside this
  patch's added lines. As a separate patch they would make this one fail its
  reverse check on a built tree as well as its forward check, and `patch`
  stops (measured 2026-09-24). Any further report on page 0xFF31 goes into
  this patch; a change outside the descriptor and the report structs can be
  a patch of its own (split-battery-source-bounds.patch).
- It builds on usb-hid-prime-on-ready.patch and sorts after it: it is a diff
  against the `usb_hid.c` that patch produces, vkey reports go through its
  queue (via `zmk_usb_hid_send_report()`), and the 0x21 path reads its
  `pending_head` and `pending_tail`.
- Descriptor items: the 16-bit page is the raw long item `0x06, 0x31, 0xFF`,
  because Zephyr's `HID_USAGE_PAGE()` emits a 1-byte item and would truncate
  it to 0x31; Logical Maximum 255 is the 2-byte `0x26, 0xFF, 0x00`, since a
  1-byte 0xFF is -1; Input is `0x02` (Data, Variable, Absolute) for a single
  value field.
- USB only, BLE HOG descoped: no canon build target presents HOG to a host.
  The vendor collection is in the HOG report map (the descriptor array is
  shared), but nothing sends there: the BLE cases return `-ENOTSUP`. A HOG
  path would need a new input-report characteristic (CCC and Report Reference)
  and a queue in `hog.c`, and its hard-coded `hog_svc.attrs[]` indices
  recomputed; zmk#3390 leaves that question open to the maintainers.
- The split battery report bypasses the pending ring:
  `zmk_usb_hid_send_split_battery_report()` writes directly and returns
  `-EAGAIN` unless the bus is up and the ring is empty. Through
  `zmk_usb_hid_send_report()`, a level would take a ring slot, and a full ring
  drops its oldest entry, so a level nobody waits for could evict a
  keystroke; and the `USB_DC_SUSPEND` case's `usb_wakeup_request()` would wake
  a sleeping host whenever a half's charge changed or a half dropped off.
  `zmk_usb_is_hid_ready()` cannot gate it: `app/src/usb.c` maps
  `USB_DC_SUSPEND` to `ZMK_USB_CONN_HID` and keeps `is_configured`, so it
  reads ready through a suspend.
- A refused level is not resent, and the next one may be hours away: a half
  sends a level only when its percentage changes and stops sampling while
  idle (ZMK `app/src/battery.c`: an event only on a change, the timer stopped
  at `ZMK_ACTIVITY_IDLE`, 30 s by default). The listener therefore stores the
  level before sending, and
  `GET_REPORT(0x21)` answers with the stored value (one instance: the source
  written last).
- The split battery report stays out of `zmk_endpoint_clear_reports()`. That
  function releases held input on an endpoint switch; a battery level is
  state, and clearing it would send a made-up `{source, 0}` at every switch.
- The Ctrl/Alt mask in `behavior_vkey.c` (2026-07-06): a vkey press masks the
  LCtrl or LAlt that the TU_LL and TU_LM thumb keys hold
  ([config/macros.dtsi](../../config/macros.dtsi)), and the mask lifts at the
  next layer-off, not per key. The reasons, including why not per key (macOS
  reads the repeated Ctrl taps as the Dictation shortcut), are in the file's
  header comment.

Known limits: one vkey at a time: a press replaces the selector and every
release sends 0, so in a roll (A down, B down, A up) the host sees B released
with A (a bitmap report would be the backward-compatible extension); vkey
reports share the ring's drop-oldest
policy, so across a long not-ready window a press can be dropped while its
release arrives, and chord sees no press.

Upstream: [zmk#3390](https://github.com/zmkfirmware/zmk/pull/3390)
(`CONFIG_ZMK_HID_VKEY`, default n; `CONFIG_ZMK_HID_VKEY_USAGE_PAGE` default
0xFF31, `CONFIG_ZMK_HID_VKEY_REPORT_ID` default 32), open since 2026-06-18.
Its diff (`gh pr diff 3390 --repo zmkfirmware/zmk`) is the vkey part of this
patch with every addition behind `CONFIG_ZMK_HID_VKEY`: no split battery
report, no Ctrl/Alt mask. canon keeps this patch until #3390 merges and does
not depend on that happening.

## When an upstream PR merges

- zmk#3385 or #3377: delete security-changed-auto-unpair.patch and set the
  merged option (`CONFIG_ZMK_BLE_AUTO_UNPAIR_ON_KEY_MISSING=y` or
  `CONFIG_ZMK_SPLIT_AUTO_UNPAIR_ON_KEY_MISMATCH=y`) in
  config/imprint_dongle.conf.
- zmk#3384: delete usb-hid-prime-on-ready.patch, set
  `CONFIG_ZMK_USB_HID_REPLAY_ON_READY=y` in config/imprint_dongle.conf (its
  defaults are this patch's values), and in vkey-report.patch make
  `ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_HID` depend on that option (or put the
  ring check under `#if`): the 0x21 path reads `pending_head` and
  `pending_tail`, which upstream defines only under it; then regenerate.
- zmk#3390: set `CONFIG_ZMK_HID_VKEY=y` in config/imprint_dongle.conf (the
  default page and report ID leave chord and the keymap unchanged) and cut
  vkey-report.patch down to what #3390 lacks: the split battery report, with
  its items moved inside upstream's `#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)`
  block and `ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_HID` depending on
  `ZMK_HID_VKEY`, and the Ctrl/Alt mask. Or get those upstream first.
- An upstream change identical to a patch does not fail the build; CI shows
  that patch as `(already applied)`.
- After deleting or cutting a patch, reset the local tree (Adding or changing
  a patch): nothing else takes the removed change out of it.
- With both patch directories empty, `patch` has nothing to do; zmk-build.yml's
  header gives the other reasons the CI build is local.
