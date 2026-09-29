# CLAUDE.md

Claude Code 向けのプロジェクト運用メモ。人間向けの概要は
[README.md](README.md) を参照。本ファイルは「壊しやすい点」と「正しい手順」に絞る。

## このリポジトリ

自分の **ZMK ファーム repo**（リポジトリルート = ZMK user-config）。1 製品 + companion 1 台:

- **imprint**: [Cyboard Imprint](https://cyboard.digital/products/imprint) キーボード
  （board=assimilator-bt / shield=imprint_left・imprint_right、board=xiao_ble/nrf52840/zmk /
  shield=imprint_dongle）。
- **Prospector Dongle** (companion, not a replacement for the Imprint Dongle):
  board=xiao_ble/nrf52840/zmk / shield=prospector from the own module
  [zmk-beacon](https://github.com/akira-toriyama/zmk-beacon). A BLE observer
  that shows both halves' battery from the Imprint Dongle's status
  advertisement; it never advertises, pairs or connects (`CONFIG_ZMK_BLE=n` in
  the shield; a Mac scan saw no advertisement from it, 2026-09-26). The screen,
  the observer and their contracts are documented in zmk-beacon's README and
  CLAUDE.md. Over USB it enumerates as one CDC ACM port
  (product `Prospector Dongle`, no HID) that exists for the 1200 baud
  bootloader entry (seen on hardware 2026-09-26). Device names are fixed
  in [docs/glossary.md](docs/glossary.md): Cyboard Imprint (the halves) /
  Imprint Dongle (the split central) / Prospector Dongle.

※ ist（トラックボール受信ドングル）は 2026-07-13 に canon から分離し、別 repo
（`zmk-ble-hid-host`）へ移した。canon には keymap も build target も残っていない。

## 用語

UI / 設定 / コード上の呼び名は [`docs/glossary.md`](docs/glossary.md) に従う
— 正規名（`keymap`, `layer`, `behavior`, `combo`, `macro`, `board`,
`shield`, `build target`, `host bridge`, …）のみを使い、`Don't call it:`
側の同義語は使わない。用語の追加・改名はコード変更と **同一 PR で**
このファイルへ反映する。


macOS 側ホストブリッジは独立リポジトリ
[`chord`](https://github.com/akira-toriyama/chord)（Swift 6 / CGEventTap
デーモン、`~/.config/chord/config.toml` 駆動）。本リポジトリは ZMK 側
（キーマップ・ファーム）のみを扱う。

設計思想は **低依存**（Python は stdlib のみ、他は shell）。重量級ツールチェーン
（Node ランタイム依存の常駐ツール等）をリポジトリに持ち込まない。リリースの
版・ノートは glyph（fleet 共通の Go バイナリ。Actions が checksum 検証つき
composite で導入）が算出し、リポジトリ側に設定も依存も持ち込まない。

## 壊しやすい点（最優先で意識する）

- **The west manifest is [config/west.yml](config/west.yml)** (not at the
  repository root); the topdir is the repository root. Two external modules:
  - Cyboard `zmk-keyboards`: the imprint's assimilator-bt board and the
    imprint_left/right/dongle shields.
  - Own `zmk-beacon`: the Prospector Dongle's `prospector` shield and the
    Imprint Dongle's status broadcaster (`CONFIG_BEACON_STATUS_BROADCAST` in
    [config/imprint_dongle.conf](config/imprint_dongle.conf); both ends of the
    payload live in its `src/status_payload.h`). Pinned by commit SHA, not by
    tag, so canon takes a change without a zmk-beacon release being published
    (decided 2026-09-26, projects t-5gxp); bump the SHA by hand after a
    zmk-beacon merge. t-ogura's `prospector-zmk-module` left the manifest on
    2026-09-27 (t-k8pk) together with `patches/modules/`.

  **canon ローカル shield は無い**（`imprint_dongle` は 2026-07-28 に Cyboard#19 で
  上流入りし、ローカル定義は撤去済み。canon 固有分は
  [config/imprint_dongle.overlay](config/imprint_dongle.overlay) 等 config/ 側）。
  board/shield の一覧（all ビルド）は [build.yaml](build.yaml) が唯一のソース。
- **ZMK は `main` 追従必須・タグ固定しない**: Cyboard の `assimilator-bt`（HWv2 版）は
  新 Zephyr ハードウェアモデルを要求する。ZMK を
  タグ（例 `v0.3.0`）固定すると CI/ローカルとも `arch.cmake` で
  `Could not find ARCH=cyboard` となりビルド不能。ZMK 公式の版固定推奨より
  この依存を優先（[config/west.yml](config/west.yml) / build.yml は `@main`）。
- **Cyboard `zmk-keyboards` は `main` でなく `zephyr-4.1` ブランチを追う**: 2026-07-07 に
  Cyboard が **main の意味を変えた**（main = ZMK `v0.3.0` pin + `assimilator-bt` を HWv1
  レイアウト `boards/arm/` へ差し戻し＝Studio 0.3.0 スタック）。canon は zmk@main
  （= Zephyr 4.1）なので main を引くと HWv1 board になり、cmake が soc Kconfig を作れず
  `Kconfig/soc/Kconfig.defconfig not found` で **assimilator-bt の 2 ターゲットだけ**落ちる
  （xiao_ble の imprint_dongle は通るので、部分的な赤に見えて紛らわしい）。HWv2 board
  （`boards/cyboard/assimilator-bt/board.yml`）は `zephyr-4.1` ブランチ側にあり、Cyboard
  自身が west.yml のコメントでそちらを案内している。系統は 2026-07-30 に
  zephyr-4.1 維持で確定（t-wz4k。dongle forward-port Cyboard#19 の merge で
  ブランチが features を受けることが実証された。2026-07-28〜30 の一時 SHA pin は
  ローカル shield 撤去とともに解除済み）。
- **単一ソース規約（eiji）**: [config/eiji_macros.dtsi](config/eiji_macros.dtsi) が唯一の
  ソース。`keymap_drawer.config.yaml` の AUTO-GENERATED ブロックは
  [scripts/gen-eiji-drawer-map.py](scripts/gen-eiji-drawer-map.py) が生成し、
  [verify-eiji-sync.yml](.github/workflows/verify-eiji-sync.yml) が CI で厳密一致を
  検証する。マーカー間を手編集しない。変更は dtsi を直し
  `python3 scripts/gen-eiji-drawer-map.py` を再実行（stdlib のみ）。
- **単一ソース規約（vkey alias）**: [config/imprint.keymap](config/imprint.keymap) の
  `&vkey <id>` が唯一のソース。The `&vkey` behavior node lives in
  [config/imprint_behaviors.dtsi](config/imprint_behaviors.dtsi).
  生成物 [config/vkey-aliases.toml](config/vkey-aliases.toml)
  （host bridge [`chord`](https://github.com/akira-toriyama/chord) の `[v-key-aliases]` へ貼る用）は
  [scripts/gen-vkey-aliases.py](scripts/gen-vkey-aliases.py) が keymap を走査して id を復号し生成、
  [verify-vkey-sync.yml](.github/workflows/verify-vkey-sync.yml) が CI で照合する。id 空間は
  imprint が `0x01` / `0x10`–`0x8D`。**`0xA0`–`0xBF` は別 repo の ist 製品向けに予約**
  （chord の id→action はホスト単位で 1 つの名前空間＝再利用すると ist のボタンが誤爆する。
  `decode()` が構造的に拒否する）。
  `config/vkey-aliases.toml` を手編集しない。id を変えるときはキーマップを直し
  `python3 scripts/gen-vkey-aliases.py` を再実行（stdlib のみ）。これでキーマップ↔chord
  config の id 二重管理を排除する（chord 側への貼り込み＝chezmoi 運用は別管理）。
- **The dongle's USB product string `Imprint Dongle` is a contract with chord**:
  chord's `VKeyHIDSource` identifies the dongle by that string (VID/PID
  `0x1D50`/`0x615E` are ZMK's defaults and identical on the ist dongle, so they
  cannot tell the two apart; measured 2026-09-24, both enumerated on one Mac).
  The string comes from the upstream shield (`zmk-keyboards`
  `boards/shields/imprint_dongle/Kconfig.defconfig` → `ZMK_KEYBOARD_NAME` →
  `USB_DEVICE_PRODUCT`). Do not override `CONFIG_ZMK_KEYBOARD_NAME` for the
  dongle in `config/`, and if upstream renames it, change chord's `productName`
  and `DEVICES` in [scripts/dongle.py](scripts/dongle.py) in the same change
  (flash-dongle.sh checks images and finds the dongle by that string, and
  `dongle.py list` / `log` find it the same way).
- **The Cyboard module defaults `ZMK_RGB_UNDERGLOW=y` for every build in the
  manifest**: `boards/shields/imprint/Kconfig.defconfig` in `zmk-keyboards` puts
  that default outside its `if SHIELD_…` guard, so a target with no
  `zmk,underglow` chosen node fails in `rgb_underglow.c` with `#error`. Every
  non-imprint target needs `CONFIG_ZMK_RGB_UNDERGLOW=n` in its conf
  ([config/prospector.conf](config/prospector.conf) has it; `config/imprint.conf`
  covers imprint_left, imprint_right and imprint_dongle, because ZMK reads the
  conf of every shield-name prefix). Measured 2026-09-25 on the first Prospector build.
- **The Imprint Dongle builds with `CONFIG_BT_EXT_ADV`** (selected by
  `CONFIG_BEACON_STATUS_BROADCAST`) and needs `CONFIG_BT_EXT_ADV_MAX_ADV_SET=2`
  in [config/imprint_dongle.conf](config/imprint_dongle.conf): the status
  advertisement is a second advertising set next to ZMK's own, and under
  `BT_EXT_ADV` the host takes ZMK's legacy `bt_le_adv_start()` from the same
  pool. The build fails on a pool of 1 (zmk-beacon's `BUILD_ASSERT`). Costs:
  about 34 KB flash / 11 KB RAM, the host on the extended HCI commands, and the
  controller's extended scan following AuxPtr fields of nearby extended
  advertisers (ZMK's Zephyr fork lacks upstream 5ce9d0c621, a malformed
  AuxPtr assert; if it ever bites, carry that fix in `patches/zephyr/`).
  Measured 2026-09-26/27 (projects t-eray): reconnects unchanged in 5 reboots
  and a half power cycle, 0 advertising errors, 255-269 payloads a minute at
  the Prospector Dongle.
- **Both dongles share the `XIAO-SENSE` bootloader volume, and
  `flash-watch.sh` / `flash-reset.sh` copy `imprint_dongle.uf2` onto any XIAO
  mount**: never put the Prospector Dongle into its bootloader while either is
  running, and never have both dongles in bootloader at the same time. Flash
  either dongle with `scripts/flash-dongle.sh <image.uf2 | prospector |
  imprint_dongle>` (`--dry-run` shows the plan, `--wait N` waits for a dongle a
  KVM switch hid). It takes the device from the USB product string inside the
  image, refuses to start while another flash-dongle.sh runs (one lock for
  both dongles, which flash-impl.sh takes too), while either runs or while
  `XIAO-SENSE` is already mounted, checks both again before the copy, and copies only when the disk
  behind `XIAO-SENSE` belongs to the USB device at that dongle's `locationID` (the
  bootloader enumerates with the app's `locationID` and USB serial, both taken
  from the port and the chip: seen on hardware 2026-09-26). The first image
  with the 1200 baud entry, and any run the script fails, go on by double-tap +
  `cp -X` by hand (README). Reflashing an unchanged image copies in about 3 s
  against about 24 s for a new one: bootloader 0.6.1 skips pages whose
  contents already match (`src/flash_nrf5x.c`) and resets only after every
  block arrived, so the short copy is not a truncated one.
- **Opening the Prospector Dongle's serial port at 1200 baud reboots it into the
  UF2 bootloader** (`CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD`, on by default in
  zmk-beacon's shield; the same code first ran as a canon patch on t-ogura's
  module, removed with that module on 2026-09-27).
  Script-only flashes on hardware 2026-09-26: two with the patch, four with
  zmk-beacon images; bootloader 0.6.1, about 2.5 s from the touch to the
  mounted volume). Any program that sets
  that rate does it, not only `flash-dongle.sh` (Arduino-style uploaders,
  a serial monitor at 1200), so never do it while `flash-watch.sh` /
  `flash-reset.sh` run: they
  would copy `imprint_dongle.uf2` onto it. Find the port by the USB product
  string `Prospector Dongle` (the contract between `CONFIG_USB_DEVICE_PRODUCT`
  in zmk-beacon's `boards/shields/prospector/prospector.conf` and `DEVICES` in
  [scripts/dongle.py](scripts/dongle.py)), never by VID/PID (the Imprint Dongle's pair) or by a
  `/dev/cu.usbmodem*` name (derived from the USB location, e.g. `211201` for
  location `0x02112000`, ioreg 2026-09-26). Since 2026-09-27 the Imprint
  Dongle's CDC port has the same handler (`CONFIG_BEACON_BOOTLOADER_ON_1200_BAUD=y`
  in [config/imprint_dongle.conf](config/imprint_dongle.conf); the product
  image carries that port even without logging). Flash it with
  `./scripts/flash-dongle.sh imprint_dongle`: the same guarded steps, with the
  owner check done by df + ioreg rather than `diskutil info`, which can answer
  "Could not find disk" right after the mount (seen once on 2026-09-27). The
  bootloader keeps the app's USB location and serial. The first image with the entry, coming
  from a product image without it, goes on by double-tap. Measured 2026-09-27
  with the t-eray images: touch to mount 2.4-2.6 s, copy 9.5-12.2 s,
  re-enumeration 0.7-1.3 s.
- **A split peripheral's slot index is its first-pairing order, persisted**:
  ZMK `app/src/ble.c` `zmk_ble_put_peripheral_addr()` stores a new peripheral's
  address in the first free slot and saves it as `ble/peripheral_addresses/<i>`;
  `central.c` `reserve_peripheral_slot()` then maps that address to the same slot
  on every reconnect and reboot. The index changes only after an NVS reset (the
  `*_RESET.uf2` flow). Two consumers depend on it: the split battery report's
  `source` (chord) and the status advertisement's half mapping (zmk-beacon's
  `src/status_broadcaster.c` writes slot 0 to the left byte and slot 1 to the
  right byte of `src/status_payload.h`).
  In the current bonds slot 0 is the left half and slot 1 the right half,
  measured 2026-09-27 by powering each half off in turn: the dongle's log showed
  `conn down` on slot 0 for the left half and on slot 1 for the right half, and
  chord's report and the Prospector's `--` moved the same way (projects t-eray).
  If the Prospector shows the halves swapped after a reset, re-pair with the left
  half powered on first. Source read 2026-09-25 (ZMK main 9ebbeff0).
- **The Prospector Dongle's GIF sprite is a local-only build of a personal
  file**: `./scripts/build-zmk.sh prospector --sprite <gif>` embeds the GIF
  (zmk-beacon `CONFIG_BEACON_SPRITE_GIF`) into `firmware/prospector-sprite.uf2`;
  flash it with `./scripts/flash-dongle.sh firmware/prospector-sprite.uf2`.
  The user keeps the GIF in `assets/` of the main checkout, whose rules are in
  [assets/README.md](assets/README.md) (`.gitignore`: `/assets/*` except that
  README and `sprite-name.sh`, and `*.[gG][iI][fF]` anywhere; each file's
  source URL goes in the ignored `assets/SOURCES.md`). A worktree gets only
  the committed two, so pass the main checkout's absolute path. This
  repository is public: never commit the GIF or anything made from it
  (frames, C arrays, previews), never name its subject in commits, PRs or
  docs, and never feed it to CI or a release. The sprite's name under the HP
  bar is the subject too: [assets/sprite-name.sh](assets/sprite-name.sh)
  derives it from the GIF's file name (extension dropped, trimmed, first
  letter upper-cased; the user's rule, projects t-er81) and the build passes
  it as zmk-beacon's `CONFIG_BEACON_SPRITE_NAME` in a Kconfig fragment
  (`$CFG/.sprite/sprite.conf`, `EXTRA_CONF_FILE`; as `-DCONFIG_...` it showed
  in west's message on a failed configure step, reproduced 2026-09-29),
  printing only its length.
  The CI / release `prospector.uf2` carries no sprite and no name, so
  flashing it (`./scripts/flash-dongle.sh prospector`) removes both from the
  device and the HP bar's box shrinks from 46 px to 28 px. The layout is
  zmk-beacon's only screen since its #19: the sprite fills the space above the
  HP bar, 2 px in from the edges (180x180 for a 90x90 px GIF above a named HP
  bar), and the HP bar shows the mean of both halves with the value on the
  bar and the sprite's name under it; the terms are in
  [docs/glossary.md](docs/glossary.md) (`sprite`, `sprite name`, `HP bar`).
  The user's picks of 2026-09-28 (projects t-dzxf) and 2026-09-28/29 (t-er81,
  layout M of twelve trials). A `dongle.py shot` of a sprite build shows the
  sprite and its name: it refuses a path in any git work tree, and the PNG never
  goes into a commit, a PR or an issue.
- **生成/ツール管理ファイルを手で整形・コミットしない**（[.prettierignore](.prettierignore) で除外済）:
  `keymap_drawer.config.yaml`（gen スクリプト）、`keymap-drawer/imprint.{yaml,svg}`
  （draw-keymap の bot が生成・コミット）、`config/imprint.json`（ツールデータ）。
- **ネットワークボリューム**: 作業ツリーは `/Volumes/...`。リポジトリ直下で
  `west update` しない（重い・汚す）。後述のスクリプトはキャッシュへ複製して
  ビルドする。
- **README は user 主体で執筆**。指示なく構成・文章を大幅に書き換えない。

## ディレクトリ構成（再構築しない）

現構成は健全。以下は ZMK / 上流ツールの制約で**移動不可**：

- `config/` `build.yaml` はリポジトリ**ルート**必須（ZMK build と west の前提）。
  `boards/` `zephyr/module.yml` はローカル shield 撤去（2026-07-30）とともに廃止
  — 復活させる時はルート必須＋ビルド側の BOARD_ROOT 配管も要復元。
- `keymap_drawer.config.yaml`（ルート）と `keymap-drawer/`（出力）の分離は
  caksoylar/keymap-drawer の既定どおりで**意図的**。"整理"して移動しない。
- `scripts/` は現規模に適切。これ以上分割しない。
- **glyph の `[[packages]]`（サブディレクトリ毎の独立版系列）は使わない**（2026-09-10 裁定、projects t-ptp3）。製品は imprint の uf2 3 つ + companion の `prospector.uf2` 1 つの 1 組で（同じ manifest・同じ patch 適用・同じ release draft。2026-09-25 t-tbaf）、`config/`・`patches/`・`build.yaml`・`config/west.yml` は全部その 1 ビルドの入力＝単独の消費者も成果物も持つディレクトリが無い。`patches/` は upstream PR で外へ出る前提（各 README）で版の単位ではなく、分けると patch だけの修正（例 #148）が firmware の版もドラフトも動かさなくなる。release.yml の uf2 添付も単一ドラフトの `.tag` 前提。

## ビルド

- ローカル: `./scripts/build-zmk.sh`（Docker。依存は `~/.cache/zmk-canon`
  に永続化、冪等。`--update` / `--clean`、シールド指定可＝サブセット（例
  `imprint_left` だけ）。出力 `firmware/`＝
  gitignore 済）。`--sprite <gif>` builds `prospector-sprite.uf2` with a GIF
  sprite (local only; see the sprite item under 壊しやすい点)。詳細は
  [scripts/build-zmk.sh](scripts/build-zmk.sh) 冒頭。
- Debugging builds: `--beacon <zmk-beacon checkout>` builds against a local
  zmk-beacon instead of the pin (never edit the cached clone: every other build
  checks it out at the pin first); `--kconfig CONFIG_X=V` and `--tag <name>`
  make variant images. `--beacon` and `--kconfig` images carry `-beacon` /
  `-kconfig`, so a bare `<shield>.uf2`, which flash-watch.sh, flash-reset.sh
  and `flash-dongle.sh <device>` take, is always a pinned build. `--logging`
  images carry a 4 KiB CDC ring at ZMK's INFO level; ZMK's split battery and
  connection lines are DEBUG only (`--kconfig CONFIG_ZMK_LOGGING_MINIMAL=n`).
  Each run ends with the images' sha256, FLASH and RAM, and the
  revisions built. The steps inside the container are
  [scripts/zmk-west.sh](scripts/zmk-west.sh), which CI runs too.
- Devices: `python3 scripts/dongle.py list` shows both dongles (port, USB
  location, serial, who holds the port); `python3 scripts/dongle.py log
  <prospector|imprint_dongle> --seconds N` reads a `--logging` image at 115200
  and exits by itself (key-event lines dropped unless `--raw`; never write raw
  logs into the repository); `python3 scripts/dongle.py shot --out <file>`
  writes a PNG of the Prospector Dongle's screen (zmk-beacon's
  `CONFIG_BEACON_SCREEN_DUMP`, any image built with it) and refuses while a log
  reader holds the port. The rate is a command: 1200 baud reboots a dongle into
  its bootloader and 2400 starts the screen dump, so never open a dongle port
  at either rate by hand.
- CI: PR / push:main で [build.yml](.github/workflows/build.yml)。実体は
  **canon ローカルの reusable [zmk-build.yml](.github/workflows/zmk-build.yml)**
  に委譲し、`patches/zmk/*`（vkey 等）と `patches/zephyr/*`（usb-hid-country-code）を
  当ててから build.yaml の全ターゲットを
  ビルドする（公式 reusable は patch を当てず &vkey 等が解決できないため差し替えた。
  背景は zmk-build.yml / [docs/vkey-roadmap.md](docs/vkey-roadmap.md)）。
- リリース: [release.yml](.github/workflows/release.yml)。**push:main で自動**に
  glyph が最後の v* タグ以降を squash-safe に歩いて次版とノートを算出し
  「ローリングドラフト」Release を upsert する（タグは作らない）。マージするほど
  下書きが育ち、**手動 Publish で初めてタグ生成 + `*.uf2` 添付**。
  `workflow_dispatch` の `dry_run=true` はドラフトを作らない完全プレビュー。

## コミット規約（必須）

**gitmoji-driven**: `<:gitmoji:>[(<scope>)][!] <subject>` — semver は gitmoji で
決まる。完全な規約・semver 表・除外規則は
**[CONTRIBUTING.md](https://github.com/akira-toriyama/.github/blob/main/CONTRIBUTING.md)** と `glyph rules` を参照。

- ローカル検証フック: clone ごとに一度 `glyph hook install`
- PR では [commit-lint.yml](.github/workflows/commit-lint.yml) が同規則で検証
- bot（`github-actions` 等）コミットは版算出・ノートから除外
- 例: `:sparkles:(keymap) 矢印レイヤーを追加` /
  `:bug:(combos) 誤爆を修正` / `:memo: 手順を追記`

## エディタ

[.vscode/settings.json](.vscode/settings.json) で保存時 prettier（md/json/yaml
のみ。`.dtsi`/`.keymap`/`.conf`/`.sh`/`.py` は対象外）。

## レビュー / コスト方針（課金回避）

- **CI で Claude（課金 API）を使わない**。PR ゲートは無料の決定的チェックのみ
  （build / commit-lint / shellcheck / draw fail_on_error / verify-eiji-sync /
  verify-vkey-sync）。
- Claude レビューが必要なときは**手元でオンデマンド**起動（`/review`,
  `/ultrareview` 等）。CI に Claude 自動レビューを足さない（増分$0 を維持）。
- public repo のため GitHub Actions 実行は無料枠。課金 API を使う workflow を
  追加しないこと。

## Claude Code

- 権限（WebFetch 許可ドメイン等）はローカルの `.claude/settings.json`（gitignore 対象）に置き、repo には commit しない（個人・マシン設定は共有しない方針・他 repo と統一）。
- 許可している WebFetch: `zmk.dev`（ZMK 公式ドキュメント）, `deepwiki.com`（repo 解説）＋ `WebSearch`。`karabiner-elements.pqrs.org` は未使用のため削除。
- 新マシンでは `.claude/settings.json` を手で再作成する（gitignore 対象＝clone で復元されない）。

## Roadmap board (GitHub Projects)

この repo の issue は集約 Project「roadmap」(akira-toriyama #5・
https://github.com/users/akira-toriyama/projects/5)で管理。Claude もこれに従う:

- 新規 issue は **Inbox** 既定。off-board の open issue を残さない(迷子を作らない)。
- Status(single-select): `Inbox → Backlog → Ready → In Progress → Done` / `Icebox`=someday。Ready は 2〜3(WIP)。
- PR 本文に `Closes #N` を必ず書く → merge で issue 自動 close → 自動 Done。
- 詳細は Project の README。
