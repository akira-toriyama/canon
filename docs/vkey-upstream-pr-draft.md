# vkey → zmkfirmware/zmk upstream PR — 提出済み [zmk#3390](https://github.com/zmkfirmware/zmk/pull/3390)

`patches/zmk/vkey-report.patch`（canon 固有の vendor-HID「オリジナルキー」）を
**汎用化して `zmkfirmware/zmk` 本体へ upstream する**ための準備一式。

> **状態: 提出済み [zmkfirmware/zmk#3390](https://github.com/zmkfirmware/zmk/pull/3390)（2026-06-18）。**
> 一般化 patch（[`vkey-upstream-pr-draft.patch`](vkey-upstream-pr-draft.patch)）を実ビルド検証
> （下記「ビルド検証結果」）→ ZMK CI 同一 clang-format で整形 → 案A（USB-only）で提出。fork PR は
> ZMK メンテナのワークフロー承認待ち（#3384/#3385 と同状態）。**マージは難航しうる（既知）。
> 未 merge の間は canon の `patches/zmk/vkey-report.patch` を維持**し、canon は upstream に依存しない。
> merge された時のみ下記「canon 側の移行」を実行。本書は
> [`docs/vkey-roadmap.md`](vkey-roadmap.md) 「未達成/保留 #6」「Upstream 収束タスク」の具体化。
> テンプレ＝兄弟 PR [zmk#3384](https://github.com/zmkfirmware/zmk/pull/3384)（What/Why/How + default-off Kconfig）。

## ビルド検証結果（DONE, 2026-06-18）

一般化 patch を実ビルドで検証済み（canon の `build-zmk.sh` 機構＝Docker /
`zmkfirmware/zmk-build-arm:stable` / ZMK main `ff09f2d0`）。手順は「キャッシュ zmk を
一般化形に直接編集 → `CONFIG_ZMK_HID_VKEY=y` → 3 ターゲットを直接ビルド」。

- ✅ **3 ターゲット全ビルド成功**（`xiao_ble/nrf52840/zmk:imprint_dongle` /
  `assimilator-bt:imprint_left` / `imprint_right`）。dongle FLASH 24.75%。
- ✅ **Kconfig 発効**: dongle `.config` に `CONFIG_ZMK_HID_VKEY=y` /
  `CONFIG_ZMK_HID_VKEY_USAGE_PAGE=0xFF31` / `CONFIG_ZMK_HID_VKEY_REPORT_ID=32` /
  `CONFIG_ZMK_BEHAVIOR_VKEY=y`。
- ✅ **ON（既定値）= 現検証済み patch とバイト一致**: dongle `.elf` に現 patch と
  完全一致の 23 byte 記述子 `06 31 FF 09 01 A1 01 85 20 09 02 15 00 26 FF 00 75 08
  95 01 81 02 C0` を offset `0x3d531`（roadmap が旧 patch で記録したのと同一 offset）で
  検出。→ usage page 分割（`0xFF31`→`0x31,0xFF`）と report id alias（`32`→`0x20`）が
  正しく効いており、**実機 e2e 証拠（Phase 6）がそのまま該当**する。
- ✅ **生成 patch はバニラ ZMK main にクリーン適用可**（`git apply --check` pass）。
  security / usb-hid-prime を reverse して vkey 変更だけを isolate 済み（11 ファイル・
  ble.c や usb-hid-prime queue を含まない＝純粋な upstream 候補 diff）。
- 🟡 **OFF（default n）の byte 一致は構造的に保証**: vkey 関連の全変更が
  `#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)` 内（hid.h=4 / hid.c=2 / usb_hid.c=2 /
  endpoints.c=3 / 各ヘッダ=1）＋ Kconfig default n。無効時は前処理で消え記述子・
  シンボルとも不変。canon keymap は `&vkey` 依存で **OFF の実ビルド検証は不可**（OFF だと
  behavior が gate offされ keymap が解決しない）ため、reviewer 流の構造論証で担保。
  ※ canon 本番は patch・キャッシュとも無傷（検証はキャッシュ直編集で実施、終了後 reset）。

成果物 = この `.md`（設計＋PR ドラフト）＋ [`vkey-upstream-pr-draft.patch`](vkey-upstream-pr-draft.patch)
（バニラ ZMK 適用可・build-verified の一般化 diff）。

## なぜ upstream するか（到達点）

現状の vkey は ZMK コアへの out-of-tree patch（`patches/zmk/vkey-report.patch`、
10 ファイル）。本体に取り込まれれば canon は **patch を撤去** → `build.yml`/
`zmk-build.yml` を **ZMK 公式 reusable** へ戻し **案1 の自前 CI を丸ごと巻き戻せる**
（保守コスト 0）。これが `patches/zmk/` を空にする終端状態の最後のピース
（`security-changed`→zmk#3385 / `usb-hid-prime`→zmk#3384 は提出済み、vkey が唯一未提出）。

## 汎用化の核心 — 「canon 固有」を「default-off で設定可能」へ

upstream 採用の必須条件は **default 無効・有効時のみ機能・無効時はバニラと
byte 一致**（#3384/#3385 と同じ流儀）。canon の固定値を Kconfig 化する:

| canon 固有（現 patch） | upstream 一般化 | 既定値 |
|---|---|---|
| usage page `0xFF31` を raw byte `0x06,0x31,0xFF` でベタ書き | `CONFIG_ZMK_HID_VKEY_USAGE_PAGE`（hex）をコンパイル時に lo/hi 分割 | `0xFF31` |
| report id `0x20`（`#define ZMK_HID_REPORT_ID_VKEY 0x20`） | `CONFIG_ZMK_HID_VKEY_REPORT_ID`（int） | `0x20` |
| descriptor/report/送出/behavior が常時コンパイル | 全て `CONFIG_ZMK_HID_VKEY`（default n）で gate | n |
| 1-byte single selector | v1 はそのまま（bitmap/複数同時は将来） | — |
| BLE は `-ENOTSUP`（descope） | **要決定**（下記） | — |
| 命名 `vkey` / "original key" | `vkey`（= vendor key）維持を提案（**要決定**） | — |

**既定値を canon の現値（`0xFF31`/`0x20`）に固定**してあるので、採用後 canon は
`CONFIG_ZMK_HID_VKEY=y` を立てるだけで **wire 互換**（chord 側の VID/PID マッチ・
`reportID==0x20`・`[v-key-aliases]` 全て不変）。

### default-off の byte 一致保証

`CONFIG_ZMK_HID_VKEY=n`（既定）のとき:
- `zmk_hid_report_desc[]` の vkey collection は `#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)`
  ブロックごと消える → **descriptor は upstream と完全一致**。
- report 構造体 / `vkey_report` state / `zmk_hid_vkey_set|clear|get` / `zmk_usb_hid_send_vkey_report`
  / `zmk_endpoint_send_vkey_report` / `get_report_cb` の `case` も全て gate → シンボル増加なし。
- `behavior_vkey.c` は `ZMK_BEHAVIOR_VKEY`（`depends on ZMK_HID_VKEY`）で未コンパイル。
- DT binding yaml が存在するだけ・インスタンス化されなければ無害。

→ 無効時のバイナリはバニラ ZMK と同一。これが採用の前提。

## Kconfig（新規）

`app/Kconfig` に追加（#3384 が `CONFIG_ZMK_USB_HID_REPLAY_ON_READY` を足したのと同じ場所・流儀）:

```kconfig
menuconfig ZMK_HID_VKEY
    bool "Vendor-defined HID selector key (vkey)"
    default n
    help
      Add an independent vendor-defined HID top-level collection that reports a
      single 1-byte selector (the "vkey" id, 1-255; 0 = released), plus a
      `&vkey <id>` behavior that emits it. This lets a keymap send original key
      codes that never collide with the standard keyboard/consumer/mouse usages;
      a host-side agent reads the vendor report and maps the id to an action.
      Disabled by default: when off, the report descriptor, report state, send
      path and behavior are all compiled out and the firmware is byte-identical
      to a build without this option.

if ZMK_HID_VKEY

config ZMK_HID_VKEY_USAGE_PAGE
    hex "Vendor usage page for the vkey collection"
    default 0xFF31
    range 0xFF00 0xFFFF
    help
      16-bit vendor-defined usage page (0xFF00-0xFFFF) the vkey collection lives
      on. Must not be a page used by other enabled collections.

config ZMK_HID_VKEY_REPORT_ID
    int "HID report ID for the vkey selector report"
    default 32
    range 4 255
    help
      Report ID for the vkey input report. Must not collide with ZMK's standard
      report IDs (1 = keyboard, 2 = consumer, 3 = mouse). Default 32 (0x20).

endif # ZMK_HID_VKEY
```

そして `app/Kconfig.behaviors` の既存 `ZMK_BEHAVIOR_VKEY` に依存を足す:

```kconfig
config ZMK_BEHAVIOR_VKEY
    bool
    default y
    depends on DT_HAS_ZMK_BEHAVIOR_VKEY_ENABLED && ZMK_HID_VKEY
```

## 一般化したコード（現 patch との差分）

現 `patches/zmk/vkey-report.patch` をベースに、固定値 → Kconfig + 全体 gate へ。
**太字＝canon patch からの変更点**。それ以外は現 patch のまま。

### `app/include/zmk/hid.h`

- `#define ZMK_HID_REPORT_ID_VKEY 0x20` を**削除**し、参照箇所を
  `CONFIG_ZMK_HID_VKEY_REPORT_ID` に置換（report id は Kconfig が単一ソース）。
- descriptor を **`#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)` で包み**、usage page を分割:

```c
#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)
    /* Vendor-defined selector key (vkey). Independent top-level collection,
     * present only when CONFIG_ZMK_HID_VKEY is enabled. The usage page is a
     * 16-bit vendor page, so the long (2-byte) global item 0x06,lo,hi is
     * written raw — HID_USAGE_PAGE() emits a 1-byte item and would truncate. */
    0x06, (CONFIG_ZMK_HID_VKEY_USAGE_PAGE & 0xFF),
          (CONFIG_ZMK_HID_VKEY_USAGE_PAGE >> 8),   /* Usage Page (vendor, 16-bit) */
    HID_USAGE(0x01),                               /* Usage (application)         */
    HID_COLLECTION(HID_COLLECTION_APPLICATION),
    HID_REPORT_ID(CONFIG_ZMK_HID_VKEY_REPORT_ID),
    HID_USAGE(0x02),                               /* Usage (selector)            */
    HID_LOGICAL_MIN8(0x00),
    HID_LOGICAL_MAX16(0xFF, 0x00),                 /* 255; signed → 2-byte item   */
    HID_REPORT_SIZE(0x08),
    HID_REPORT_COUNT(0x01),
    HID_INPUT(ZMK_HID_MAIN_VAL_DATA | ZMK_HID_MAIN_VAL_VAR | ZMK_HID_MAIN_VAL_ABS),
    HID_END_COLLECTION,
#endif /* CONFIG_ZMK_HID_VKEY */
```

- report 構造体 + `zmk_hid_vkey_set/clear/get` 宣言を **`#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)`** で包む。
  `report_id` の初期化は `CONFIG_ZMK_HID_VKEY_REPORT_ID` を使う。

> `(CONFIG_ZMK_HID_VKEY_USAGE_PAGE & 0xFF)` / `>> 8` は配列初期化子内のコンパイル時
> 定数式（`0xFF31`→`0x31,0xFF`）。`HID_REPORT_ID(32)` は `0x85,0x20` に展開。OK。

### `app/src/hid.c`

`vkey_report` state と set/clear/get 実装を **`#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)`** で包む。
`.report_id = CONFIG_ZMK_HID_VKEY_REPORT_ID`。

### `app/src/usb_hid.c`

`zmk_usb_hid_send_vkey_report()` と `get_report_cb` の case を gate。case ラベルは
`case CONFIG_ZMK_HID_VKEY_REPORT_ID:` に（`#if` 内）。

### `app/src/endpoints.c`

`zmk_endpoint_send_vkey_report()` と `zmk_endpoint_clear_reports()` の vkey clear+再送を gate。
**BLE 分岐は下記「要決定」次第**。

### `app/include/zmk/{usb_hid,endpoints}.h`

宣言を `#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)` で包む。

### `app/src/behaviors/behavior_vkey.c` / `zmk,behavior-vkey.yaml` / `CMakeLists.txt`

現 patch のまま（`target_sources_ifdef(CONFIG_ZMK_BEHAVIOR_VKEY ...)`）。`ZMK_BEHAVIOR_VKEY`
が `ZMK_HID_VKEY` 依存になるので、HID gate と自動連動。yaml の description を汎用文言に。

## 要決定事項（提出前にユーザー確認）

1. **BLE-HOG をどうするか（最大の論点）。** ZMK は BLE 第一なので、reviewer は
   USB だけでなく BLE-HOG 送出も求める可能性が高い。
   - **案 A（推奨・v1）**: USB のみ実装。BLE 分岐は `-ENOTSUP` + 「follow-up」と明記。
     実機検証済み（canon の dongle→USB）の範囲だけを出す。descriptor は共有なので
     vkey collection は HOG report map には**載る**（送出経路が無いだけ）。reviewer に
     「BLE は次段で」と説明。**リスク**: 「BLE 無しは中途半端」と難色の可能性。
   - **案 B**: `zmk_hog_send_vkey_report` を実装（新 GATT input characteristic + CCC +
     report-ref + msgq + `hog_svc.attrs[N]` index）。採用率は上がるが **canon に
     HOG-to-PC build target が無く実機未検証** + `hog.c` の hardcoded attrs index が
     最も脆い（roadmap 未達成 #1 で指摘済み）。出すなら別途実機検証環境が要る。
   - スケッチ（案 B 着手時）: `hog.c` に keyboard/consumer と同型の characteristic を
     1 本追加（`BT_GATT_CHARACTERISTIC` + CCC + report reference descriptor で report id
     を申告）→ `zmk_hog_send_vkey_report` を msgq 経由で。attrs index 計算が hardcoded
     なので vkey 追加で既存 index がずれる点に注意。

2. **命名**。`vkey` / `ZMK_HID_VKEY` / `&vkey` / `behavior-vkey` を維持する案
   （churn 最小・chord wire 不変）。reviewer が `vendor-key` / `raw-hid` 等を好む
   可能性。改名する場合 canon keymap（`&vkey <id>`）と chord（`[v-key-aliases]`・
   `vkey-aliases.toml` 生成器）も追随が要る。**維持を推奨**。

3. **usage page / report id を設定可能にするか、固定にするか。** 設定可能（本案）は
   柔軟だが Kconfig が増える。「vendor page は元々ユーザー定義領域だから固定で十分」
   という反論もあり得る。**設定可能を推奨**（vendor page 衝突回避・汎用性）。

4. **selector 幅**。1-byte（255 id・同時 1 個）で v1。bitmap（複数同時）は将来拡張と
   明記（独立 collection なので後方互換に拡張可）。

## canon 側の移行（採用・merge されたら）

1. `config/imprint.conf`（または該当 .conf）に
   `CONFIG_ZMK_HID_VKEY=y` を追加（usage page/report id は既定 0xFF31/0x20 のままで可）。
2. `patches/zmk/vkey-report.patch` を削除、`patches/zmk/README.md` の該当節も削除。
3. `patches/zmk/` が空になれば `build.yml`/`zmk-build.yml`/`release.yml` を ZMK 公式
   reusable へ戻す（案1 の巻き戻し）。`security-changed`/`usb-hid-prime` も merge 済みが前提。
4. chord 不変（wire 互換）。canon keymap 不変（`&vkey <id>` のまま）。

## PR ドラフト本文（提出時にそのまま貼る — #3384 流の What/Why/How）

> 下記は **案 A（USB-only v1）** 前提のドラフト。BLE を入れる（案 B）なら How/Why に
> HOG 段落を追加。

---

**Title:** `feat(hid): optional vendor-defined selector key (vkey) behavior`

### What

Add `CONFIG_ZMK_HID_VKEY` (default `n`). When enabled, ZMK gains:

- an independent vendor-defined HID top-level collection that reports a single
  1-byte selector — the "vkey id" (`1`–`255`; `0` = released) — on a
  configurable vendor usage page (`CONFIG_ZMK_HID_VKEY_USAGE_PAGE`, default
  `0xFF31`) and report ID (`CONFIG_ZMK_HID_VKEY_REPORT_ID`, default `0x20`);
- a `&vkey <id>` behavior that, on press, sets the selector to `<id>` and sends
  the report, and on release sets it to `0` and sends.

When disabled (the default) the report descriptor, report state, send path and
behavior are all compiled out — the firmware is byte-identical to a build
without the option.

### Why

Some setups want to send "original" key codes that are guaranteed never to
collide with any standard keyboard/consumer/mouse usage, and have a host-side
agent map them to actions (launch apps, window management, IME toggles, …).
Today that requires either reusing function-row/consumer codes (which collide
with real shortcuts) or out-of-tree patches. A vendor-defined selector report
is the HID-correct way to carry such codes: the host sees a distinct vendor
collection it can match exclusively, and normal typing is untouched because the
codes live on a vendor page no application reads.

This has been running as an out-of-tree patch on a Cyboard Imprint (dongle →
USB) for [time]; the host agent is a small macOS daemon that reads the vendor
report via IOHIDManager. Upstreaming it behind a default-off Kconfig lets others
use the mechanism without a fork, at zero cost to builds that don't enable it.

### How

- **Descriptor** (`hid.h`): under `#if IS_ENABLED(CONFIG_ZMK_HID_VKEY)`, append an
  independent Application collection (Report ID = `CONFIG_ZMK_HID_VKEY_REPORT_ID`,
  one 8-bit Data/Var/Abs field, logical 0–255) after the standard collections.
  The 16-bit vendor usage page is written as a raw long item
  (`0x06, lo, hi`) because `HID_USAGE_PAGE()` emits a 1-byte item; the bytes are
  derived from the Kconfig value at compile time.
- **Report state** (`hid.c`): a `struct zmk_hid_vkey_report` plus
  `zmk_hid_vkey_set/clear/get`, all gated.
- **Send path** (`usb_hid.c`, `endpoints.c`): `zmk_usb_hid_send_vkey_report` and
  `zmk_endpoint_send_vkey_report`, mirroring the consumer report path, and a
  `GET_REPORT` case for the new report ID. `zmk_endpoint_clear_reports` also
  clears+resends the vkey selector on endpoint switch, so a held vkey can't get
  stranded on the host.
- **Behavior** (`behavior_vkey.c` + DT binding): a one-parameter behavior that
  runs on the central (where HID state and the USB endpoint live) and directly
  sets/sends the selector — it does not raise a keycode event, since the vendor
  selector isn't a KEY/CONSUMER usage.
- BLE HOG send is out of scope for this PR (USB transport only); the vendor
  collection still appears in the HOG report map because the descriptor is
  shared, so adding a HOG send path later is additive.

### Testing

- `CONFIG_ZMK_HID_VKEY=n` (default): report descriptor and symbols unchanged
  (diff the generated descriptor / `.elf`); confirmed byte-identical.
- `CONFIG_ZMK_HID_VKEY=y`: built for [board]; `&vkey <id>` press/release emits a
  2-byte report `[report_id, id]` / `[report_id, 0]`; verified on macOS via
  IOHIDManager (host reads `reportID == 0x20`, selector = `report[1]`); normal
  typing unaffected; held vkey cleared on endpoint switch.

---

## 次のステップ（決定後）

1. ~~generalized `.patch` 作成 + build-verify~~ **✅ DONE**（上記「ビルド検証結果」。
   patch = [`vkey-upstream-pr-draft.patch`](vkey-upstream-pr-draft.patch)）。
2. 上記「要決定事項」をユーザーが確定（特に **BLE 案 A/B**・命名）。案 B（BLE-HOG 実装）を
   選ぶ場合のみ `zmk_hog_send_vkey_report` 追加 + HOG-to-PC 検証環境が要る（再 build-verify）。
3. ZMK contributor 手順（commit 規約・`pre-commit` / clang-format・PR テンプレ）に整える。
   clang-format で descriptor の手動整形が崩れないか確認。
4. `zmkfirmware/zmk` へ提出（**ユーザーの明示 go 後**）。merge されたら canon は
   「canon 側の移行」節（Kconfig 立てる → patch 撤去 → 案1 巻き戻し）を実行。
