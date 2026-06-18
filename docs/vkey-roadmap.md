# vkey (ベンダー定義 HID オリジナルキー) ロードマップ

ZMK (canon) から、既存のどのキー入力とも衝突しない **オリジナルキー
(連番 ID)** をベンダー定義 usage page で送出し、macOS host bridge
([`chord`](https://github.com/akira-toriyama/chord)) が IOHIDManager で
受けて action にマップする経路を追加する作業の全体計画。複数セッションに
またがるため、状況・残タスク・判断・**未達成/保留**をここに集約する。

元指示書: `~/Downloads/vkey-vendor-hid-spec.md`。本書は指示書の Phase 0
(前提調査・判断記録) と、それを実コードに突き合わせた実装計画・引き継ぎ。

> 進め方の前提: ユーザー指示で**マルチエージェント (ultracode) 運用**・
> **計画/実行のセッション分割可**・**引き継ぎメモ必須**・**未達成を暗黙に
> しない**。本書はその引き継ぎメモを兼ねる。

## スコープ (確定)

- **対象構成: キーボード → ドングル → PC (USB HID)**。これが日常運用で、
  唯一の必須 transport。ドングル (XIAO BLE = BLE central) が PC へ USB HID
  を提示し、左右半分は**ドングルへの BLE peripheral**(split protocol、HOG
  ではない)。`&vkey` behavior は central(ドングル)で実行され、ドングルの
  USB endpoint からベンダーレポートを送る。
- **BLE-HOG 直結 (キーボード単体を PC へ BLE) は descope(保留)**。現行
  canon に HOG を PC へ提示する build target が無い(半分は
  `SPLIT_ROLE_CENTRAL=n` の peripheral)。指示書の受け入れ条件は「USB と BLE
  両方」だが、本計画は **USB のみ充足**。BLE は明示的に「[未達成/保留](#未達成--保留-未達成を暗黙にしない)」
  として追跡する(暗黙に落とさない)。
- **chord の修正可**(ユーザー承認済)。Phase 4〜6 は chord 側。

## アーキテクチャ判断 (指示書 Phase 0 判断ポイント①の結論)

**descriptor 直接パッチ (`patches/zmk/`) を採用。`badjeff/zmk-hid-io`
モジュールは不採用。**

- 根拠1: ZMK は単一の `zmk_hid_report_desc[]` を USB
  (`usb_hid_register_device`) と BLE (`read_hids_report_map`) の**両方**が
  `sizeof()` で参照する。ベンダー collection を 1 つ append すれば両 report
  map に自動的に乗る(長さ定数の更新不要)。
- 根拠2: `zmk-hid-io` は USB interface 数(`CONFIG_USB_HID_DEVICE_COUNT`)を
  増やす作りで、BLE-HOG 非対応。
- 根拠3: canon は C ソースを持たない(`zephyr/module.yml` は `board_root`
  のみ)。ZMK コア改変は既存の **`patches/zmk/` 機構**(build-zmk.sh が
  `git -C zmk apply` で冪等適用)に乗せるのが唯一筋の通る方法で、実績もある
  (`security-changed-auto-unpair.patch` / `usb-hid-prime-on-ready.patch`)。

### 設計パラメータ (確定)

| 項目 | 値 | 備考 |
|---|---|---|
| Vendor Usage Page | `0xFF31` | 16-bit page。**raw long item が必須**(下記) |
| Usage (collection) | `0x01` Application | IOHIDManager の device match キー |
| Usage (selector field) | `0x02` | IOHIDManager が値要素として読む |
| Report ID | `0x20` | **空き確認済**(既存は 0x01 kbd/leds, 0x02 consumer, 0x03 mouse のみ。cache hid.h:75-78) |
| レポート形式 | 1 byte selector | `0`=解放 / `1..255`=有効 ID。1 度に 1 キー |
| keymap 構文 | `&vkey <id>` | press で id 送出、release で 0 送出 |

### 検証済みディスクリプタ bytes (adversarial verify 済)

`zmk_hid_report_desc[]` の**末尾**(全 collection の後、`};` の直前。cache
では hid.h:256)へ以下 **23 byte** を append する。`#if CONFIG_ZMK_POINTING`
ブロックの外なので POINTING 有無に依らず常に存在する。

```
06 31 FF   ; Usage Page (Vendor 0xFF31)   ← raw long item 必須(下記★1)
09 01      ; Usage (0x01) application
A1 01      ; Collection (Application)
85 20      ; Report ID (0x20)
09 02      ; Usage (0x02) selector
15 00      ; Logical Minimum (0)
26 FF 00   ; Logical Maximum (255)         ← 2 byte 必須(下記★2)
75 08      ; Report Size (8)
95 01      ; Report Count (1)
81 02      ; Input (Data,Variable,Absolute)← 0x02 必須(下記★3)
C0         ; End Collection
```

マクロ形(usage page 以外は既存の HID_* マクロで配列スタイルに合わせる):

```c
/* hid.h:75-78 付近に追加 */
#define ZMK_HID_REPORT_ID_VKEY 0x20

/* zmk_hid_report_desc[] の末尾、`};` 直前に追加 */
    /* === Vendor-defined "original key" (vkey) selector === */
    0x06, 0x31, 0xFF,                                  /* Usage Page (Vendor 0xFF31) ★1 */
    HID_USAGE(0x01),                                   /* Usage (application)           */
    HID_COLLECTION(HID_COLLECTION_APPLICATION),
    HID_REPORT_ID(ZMK_HID_REPORT_ID_VKEY),             /* 0x20                           */
    HID_USAGE(0x02),                                   /* selector                      */
    HID_LOGICAL_MIN8(0x00),
    HID_LOGICAL_MAX16(0xFF, 0x00),                     /* 255 ★2                        */
    HID_REPORT_SIZE(0x08),
    HID_REPORT_COUNT(0x01),
    HID_INPUT(ZMK_HID_MAIN_VAL_DATA | ZMK_HID_MAIN_VAL_VAR | ZMK_HID_MAIN_VAL_ABS), /* 0x02 ★3 */
    HID_END_COLLECTION,
```

**指示書のコード片からの修正点(コンパイル検証で確定)**:

- **★1**: `0xFF31` は 16-bit。Zephyr の `HID_USAGE_PAGE()` は `bSize=1`
  固定で、`HID_USAGE_PAGE(0xFF31)` は `05 31` を吐き **0xFF を捨てる**
  (clang `-Wconstant-conversion` も出る)。`HID_USAGE_PAGE16` は ZMK/Zephyr
  に存在しない。よって **raw bytes `0x06,0x31,0xFF` をベタ書き**する。
- **★2**: Logical Maximum は符号付き。1 byte の `25 FF` は -1 と解釈され
  min0 > max-1 で不正。`26 FF 00`(+255)が必須。指示書も `26 FF 00` で正。
- **★3**: Input は **`81 02` (Data,Variable,Absolute)**。指示書の `81 00`
  (Array) は誤り(Array は Usage Min/Max のテーブルを前提とする。ここは単一
  Usage の値フィールドなので Variable が唯一正しい。macOS IOHIDManager も値
  要素 1 個として素直に surface する)。

> 検証手段: HID 1.11 短項目規則からの独立再導出 + 実際の Zephyr マクロを
> clang でコンパイルした両方で、上記 23 byte が byte-for-byte 一致。

## フェーズと状態

| Phase | 内容 | repo | 状態 |
|---|---|---|---|
| 0 | 前提調査・アーキテクチャ判断・本書作成 | canon | ✅ 完了 |
| 0.5 | **fresh main 再検証ゲート**(下記) | canon | ✅ 完了 (main `ff09f2d0`、対象ファイル drift 無し) |
| 1 | descriptor + report 配管 + `&vkey` behavior を 1 patch に | canon | ✅ 完了 (`patches/zmk/vkey-report.patch`) |
| 1G | ビルドゲート(3 target ビルド + 冪等再適用 + 周辺非コンパイル) | canon | ✅ 完了 + 敵対的レビュー pass |
| 2 | **実機 USB raw report 観測ゲート(鉄則)** | canon+実機 | ✅ 通過 — wire=`[0x20, selector]` / sel=`report[1]` |
| 3 | 本番 keymap への `&vkey` 配置確定 | canon | ✅ 完了(本番 migration で 4 層+X_1 全置換) |
| 4 | chord: `[[vkey]]` config(Core のみ、IOKit 非依存) | chord | ✅ 完了 → **設計転換で `[[vkey]]` は撤去**(下記) |
| 5 | chord: VKeyHIDSource(IOHIDManager)+ 配線 + 権限 | chord | ✅ 完了(`swift build` clean + 敵対的レビュー 4 件全修正) |
| 6 | chord: 実機 end-to-end + docs 改訂 | chord+実機 | 🟡 e2e ✅全層成立 / docs 改訂(non-goals/README)残 |
| 7 | **本番 migration(4 層+X_1)+ 設計転換 + 全層 e2e** | 全 | ✅ 実機成立(下記「本番 migration DONE」) |
| A | **単一ソース生成 + CI 照合(重複管理排除)** | canon+chord | ⬜ **MUST・未着手**(ユーザー必須指定) |

凡例: ✅ 完了 / 🟡 進行中 / ⬜ 未着手。**未達成は [専用節](#未達成--保留-未達成を暗黙にしない)で別途追跡**。

## 本番 migration DONE + 設計転換 (2026-06-18, 実機成立)

**設計転換(ユーザー発案・原案より良い):** vkey を独立 `[[vkey]]` テーブルにせず、**`Trigger` の 1
ケース**(`Trigger.vkey(UInt8)` / `.anyVKey`)にし、通常 `[[bindings]]` が **bare `input =
"<alias>"`**(`$` 無し=完結トリガー、`f13` と同列)で選ぶ。alias は新 `[v-key-aliases]` 表
(`NAME = <id>`、例 `TU_LL_C = 0x26`)で解決。**vkey が通常 binding として `Matcher`+`handle()`
を通る**ので **apps / when-var / onUp / pendingUps / recordFire / pause が全部タダで効く** —
これが app 振り分け(同キーでアプリ別動作)と when-var(j-layer)を可能にした(旧 flat `[[vkey]]`
では不可能)。旧 flat 経路(VKeyBinding/`[[vkey]]` parse/publishVKeys 等)は**撤去**。`.anyVKey` =
`input = "v-key"` wildcard(fallback 専用)= 共通ビープ(旧 4 本の `$PREFIX - *` を 1 本へ)。

**移行内容(機械適用、採番 `LL=0x10+n/LM=0x30+n/RM=0x50+n/RR=0x70+n/KP_X1=0x01`、n=QWERTY 0..29、
121 alias 生成):** canon keymap LL/LM/RM/RR 119 キー + DEFAULT X_1 → `&vkey <id>`(FUNCTION
テスト 0x2A は TU_LL_M と衝突するため `&none` に戻す);live `~/.config/chord/config.toml` に
`[v-key-aliases]` + 11 binding を `input="$ULTRA_LL - x"`→`"TU_LL_X"` + `kp_1`→`KP_X1` + ビープ
4→1(`input="v-key"`)+ `[input-aliases]` 撤去。**全層 e2e 実機成立**(LL+C app 振り分け / LL+A
AltTab / LL+J→K when-var / 未割当ビープ / X_1 mission-control)。**敵対的レビュー(4 観点)= 確定
4 件全修正**(機能/採番整合のバグはゼロ):`[v-key-aliases]` を SchemaDescriptor 登録(新 `openIntMap`)
+ schema 再生成 / vkey は `[[sequence]]`/`[[remap]]` 非対応(修飾子合成と非互換)を明確 reject /
専用 warning kind / 古コメント。`swift build` clean、`Chord.app` 再配置済。

**残(全て未コミット):** ① **「A」= 単一ソース生成 + CI 照合(ユーザー MUST、重複管理排除)** —
keymap↔config の id 二重管理を canon eiji パターン(`gen-eiji-drawer-map.py`→`verify-eiji-sync.yml`)
で解消。`/tmp/gen-vkey-map.py`・`/tmp/migrate-chord-config.py` がその前身。② **chezmoi re-add**
(移行後 live config を dotfiles へ取込。source は旧版のまま。backup=`config.toml.pre-vkey-bak`)。
③ commits/PR(canon/chord/dotfiles)。④ docs(non-goals/README)。⑤ chord TOML 分割(別フェーズ)。

## PR / マージ 状況 + canon CI blocker (2026-06-18)

- **chord: マージ済**（PR #97 squash→main、issue #96 close）。CI は test 2 件修正
  (ConfigSchemaShapeTests のセクション一覧に `v-key-aliases` 追加 / VKeyTests の alias 名
  `H`/`D` が実 keycode と衝突→`VKHEX`/`VKDEC` へ)。
- **canon: PR #51 OPEN/RED・別セッションで「案1」着手と決定**。ローカルは `feat/vkey` ブランチ
  維持(keymap=移行済=焼いた dongle と一致。`main` に戻さない)。

### canon CI blocker の正体（次セッションの起点）

vkey は ZMK **コア patch** 必須(`patches/zmk/vkey-report.patch` が hid.h/hid.c/usb_hid.c/
endpoints.c/CMakeLists/Kconfig.behaviors + behavior_vkey.c + DT binding yaml の 10 ファイル)。
だが `build.yml` は ZMK 公式 reusable
(`uses: zmkfirmware/zmk/.github/workflows/build-user-config.yml@main`)で**素の ZMK**をビルドし
`patches/zmk/` を当てない(patch は `build-zmk.sh`=ローカル専用)。`zephyr/module.yml` も
`board_root: .` のみで behavior を module 提供不可(かつ behavior は patch 済みコア symbol を呼ぶ)。
→ コミットした keymap の `&vkey`/`vkey:` が CI で DT エラー
`binding controller /behaviors/vkey ... lacks binding` → 3 target 全滅。

### 案1（実装済み 2026-06-18 — ブランチ `feat/vkey-migration`）

`build.yml` を reusable `uses:` から**自前ジョブ**へ: canon checkout → west + ZMK@main → 
`git -C zmk apply patches/zmk/*.patch`(`LC_ALL=C` 順、`build-zmk.sh` の適用ロジックを移植)→ 
3 target(build.yaml の matrix)ビルド → artifact upload。CI モデルが「素ビルド検証」→「patch
済みファーム build」へ(既存 security-changed/usb-hid-prime も適用=より正確)。`release.yml` も
同じ patch 適用が要る(公開リリースの firmware も patch 必須なため)。

#### 実装内容

- **`.github/workflows/zmk-build.yml`(新規・ローカル reusable)**: 実体。`matrix` job が
  `build.yaml` の include を awk+jq で動的生成(単一ソース維持)→ `build` job が
  `zmkfirmware/zmk-build-arm:stable` コンテナで west init/update → **patch 適用**(build-zmk.sh と
  同一の冪等ロジック)→ `west build`(`BOARD_ROOT`/`DTS_ROOT`=canon root)→ uf2 を artifact 化。
- **`.github/workflows/build.yml`(薄いラッパー化)**: トリガー(push:main / PR / dispatch /
  週次)+ `jobs.build.uses: ./.github/workflows/zmk-build.yml` だけ。**呼び出し元 job を `build`
  のままにすることで**ステータスチェック名 `build / Build (<board>, <shield>)` を維持し、main 保護
  ruleset の必須チェック(`build / Build (assimilator-bt, imprint_left|right)`)を**変えずに**通す。
- **`.github/workflows/release.yml`**: docker build ブロックの `west update` 後に同じ patch 適用
  ステップを追加。

#### 検証済み

- **patch 適用**: clean な現行 ZMK main(`ff09f2d0` = `zmkfirmware/zmk` の実際の最新 main)へ
  security-changed → usb-hid-prime → vkey を `LC_ALL=C` 順で**累積クリーン適用**できることを確認。
  さらに clean 状態からの `scripts/build-zmk.sh`(Docker)で **3 target 全ビルド成功**。
- **board variant drift は非問題**。`The selected board is not set up for ZMK / variant available`
  は ZMK **公式 reusable の build 後ゲート固有**の警告で、素の `west build`(build-zmk.sh・本自前
  ジョブ)はこのゲートを通らないため assimilator-bt は無改変でビルドできる。**build.yaml の board 名
  を `/zmk` variant に変える必要は無い**。
- **`actionlint`(embedded shellcheck 込み)で 3 workflow 全クリア**。matrix 動的生成(awk→jq)の
  出力が `build.yaml` の 3 ペアと一致。**実 CI でも `lint`・`build / matrix` pass + チェック名が
  ruleset 必須名と一致**することを確認(ブランチ保護無変更で通る)。

#### ⚠️ 詰まりどころ: patch パスは絶対パス必須（初回 CI が検知）

初回 push で 3 target が「パッチが当たりません: security-changed-…」で落ちた。原因は **ZMK drift
では無く** patch ステップのパス解決バグ: `for p in patches/zmk/*.patch`（相対）+
`git -C zmk apply "$p"` は `-C zmk` のため patch ファイルを **zmk/ 基準**で探し
`zmk/patches/zmk/…`（不在）を見て `No such file` → `--check` 失敗を「当たらない」と誤判定していた。
build-zmk.sh は `/workspace/patches/zmk/*.patch` の**絶対パス**なので無問題だった。修正 = workflow も
`"$GITHUB_WORKSPACE"/patches/zmk/*.patch` / `/w/patches/zmk/*.patch` の絶対パスへ。
**教訓**: ローカル `build-zmk.sh --update` がキャッシュの zmk を dirty（patch 既適用）のまま残すと
west update が最新 main へ進めず stale commit で「既適用 skip」する → **ローカル成功が CI を保証
しない**。CI（fresh checkout）が真の oracle。検証は clean な zmk から累積適用すること。

参考=動いている `scripts/build-zmk.sh`。

## 実装ログ (2026-06-18)

Phase 0.5〜1G を実機 flash 無し(Docker ビルド + 成果物検査)で完了:

- **Phase 0.5**: `build-zmk.sh --update` で ZMK main を `ff09f2d0` に更新。対象
  ファイル群は旧 cache から drift 無し(patch anchor 有効)。3 target ベースラインビルド OK。
- **Phase 1**: `patches/zmk/vkey-report.patch`(10 ファイル: 8 改変 + 新規
  `behavior_vkey.c` / `zmk,behavior-vkey.yaml`)+ `patches/zmk/README.md` +
  canon config(`vkey:` node・テスト `&vkey 42` を FUNCTION レイヤー右手上段左 =
  通常 Y 位置に配置)。descriptor は検証済み 23 byte(`06 31 FF … 81 02 C0`)。
- **Phase 1G(全クリア)**: 3 target ビルド成功 / patch は `usb-prime` の後に
  クリーン適用 + 冪等(reverse-check skip) / `behavior_vkey.c` は**ドングルのみ**
  コンパイル(left/right 除外) / `CONFIG_ZMK_BEHAVIOR_VKEY=y` / **ベンダー記述子
  23 byte がドングル `.elf` に存在**(`@0x3d531`) / dts が `&vkey` 解決。
- **敵対的レビュー(C 正しさ / HID プロトコル / build・gating / chord 契約 の 4
  観点 + 各指摘を verify)**: 確定した実害 **0 件**。確認された正の点: behavior は
  central(ドングル)実行 / HID の mutate+send は単一スレッドで直列化 → race 無し /
  on-wire は厳密に `{0x20, id}`(sizeof==2)/ 既存 collection 不変 / endpoint 切替時の
  vkey clear は**旧** endpoint へ release を送る正しい順序。
- low の観察(実害なし、chord 向け注記):
  (a) endpoint 切替 / soft-off で vkey clear(selector `0`)が送られる → chord は
  `0` を「release / latch クリア」として扱う設計なので無害。**`0` に対して action を
  発火させない**(edge 検出必須)。
  (b) USB endpoint 未選択(NONE)時の vkey press は送信されない(返値 0)=
  keyboard/consumer と同挙動。

**未コミット**(doc・patch・config はディスク上のみ)。次は **Phase 2(実機 flash・
ユーザーの番)**。

## 実装ログ Phase 5 (2026-06-18, chord repo)

chord 側に IOHIDManager 経路を実装(全て chord repo、未コミット):

- **新規 `Sources/ChordAdapterMacOS/VKeyHIDSource.swift`**: IOHIDManager。VID/PID
  `0x1D50/0x615E` で dongle を match(0xFF31 usage page では surface しない実機事実に従う)
  → device-matching callback → **単一共有バッファ**で `IOHIDDeviceRegisterInputReportCallback`
  → `reportID==0x20` 確認・selector=`report[1]`(実機契約)。`@MainActor start/stop`、
  `CFRunLoopGetCurrent()`+commonModes、`Unmanaged.passUnretained`(EventTap と同 idiom)。
  open 失敗(=Input Monitoring 不許可)は throw、Controller が catch して**デーモンは継続**。
- **`Controller.swift`**: `vkeySource` 所有、`handleVKey`(edge 検出=press 毎 1 回 / `0`=release
  / A→B roll)、`fireVKeyPress/Release`・`applyVKeyAction`(既存 `fireBindingAction` と同じ
  state interception)、`publishVKeys`(id→binding 表を lock 付き global へ publish)、
  `maybeStartVKeySource`(**vkey 設定がある時だけ**起動=非 vkey ユーザーは権限要求されない)、
  reload で latch リセット。
- **`ActionDispatcher.swift`**: `dispatch(action:name:)` 追加(VKeyBinding は Binding と別型
  なので Action 直接実行)。既存 `dispatch(_:)` はそこへ委譲(挙動不変)。
- **`Permissions.swift`**: `isInputMonitoringTrusted`/`promptForInputMonitoring`
  (`IOHIDCheckAccess`/`IOHIDRequestAccess` + `kIOHIDRequestTypeListenEvent`)。
- **`Main.swift`**(doctor に `input monitoring:` 行、advisory=`bad` にしない)/
  **`QuerySchema.swift`+`QueryServer.swift`**(`--status` に `input_monitoring_granted`、
  init param は default 付き=既存 test 無改変でコンパイル)。
- **`Info.plist` / `Info.plist.dev`**: `NSInputMonitoringUsageDescription`。

**検証**: `swift build` clean(IOKit リンク込み=**Phase 5 ビルドゲート ✅**)。`config --doctor`
が `input monitoring:` 行を表示、vkey fixture(toggle-var/hold-var/keys/dup/範囲外)の
`--validate` も Phase 4 parse に回帰なし。**`swift test` はローカル不可(要 full Xcode)→ CI**。

**敵対的レビュー(concurrency・IOKit・edge ロジック・回帰 の 4 観点 + 各指摘を独立検証)**:
確定 4 件を**全修正**:
1. (medium) **pause 中の latch 破壊**: `isPaused()` が latch 更新の前で return していたため、
   pause 中に release(0)が落ちると `lastVKeyDown` が held id のまま固着し次回 press が wedge。
   → latch 更新を pause check の**前**に移動(latch は常に wire に同期、pause は dispatch のみ抑止)。
2. (low) **replug バッファリーク**: device-match 毎にバッファ確保で removal callback 無し →
   sleep/replug で漏れ。→ **単一共有バッファ**化(replug で同一バッファを再登録、漏れ皆無)。
3. (low) **toggleVariable RMW race**: read(snapshot)→write(applyVariable) で stateLock が
   開く。Phase 5 で main スレッド writer が増え、tap スレッドと lost-update。→ 単一 lock
   窓の `applyToggleVariable` を新設し tap/vkey 全 toggle 経路を集約(既存 tap 経路も堅牢化)。

**pause 中に hold-var vkey を release した場合に変数が残る**点は tap 経路の修飾子 hold-var と
**同挙動**(pause は粗い停止、reload で state クリア)。新規欠陥ではないので許容。

次は **Phase 6(実機 e2e + docs、ユーザーの番)**。

## 実装ログ Phase 6 e2e (2026-06-18, 実機成立)

**全経路を実機で検証成立。** 手順:

- chord を Phase 5 ビルドで `./package.sh`(永続署名 `chord-dev`)→ `~/Applications/Chord.app`
  へ配置 → 起動。`ax_granted=True` / **`input_monitoring_granted=True`**(両権限付与済)。
  `vkey-hid: installed (matching VID=0x1D50 PID=0x615E, reportID=0x20)`。
- **dongle 焼き直しが必須だった**: 検証開始時の dongle は別ファーム("XIAO HOGP Probe",
  Zephyr `0x2FE3:0x0004`)で chord がマッチせず。`./scripts/build-zmk.sh imprint_dongle`
  (vkey patch 込み、`behavior_vkey.c` コンパイル・記述子 `06 31 FF` を .elf 確認)で
  `firmware/imprint_dongle.uf2` を生成 → XIAO double-tap reset → `/Volumes/XIAO-SENSE` へ
  UF2 コピー → 再起動で **`0x1d50:0x615e` に再列挙** → chord が `vkey-hid: matched Imprint
  device, input-report callback armed`。
- **発火確認**: FUNCTION 層・右手上段左 `&vkey 42` 押下 → `recent-fires` に `vkey-e2e-test`、
  `dispatch.shell: vkey-e2e-test → say vkey`。**2 回の押下が ~1s 間隔で 2 件**=edge 検出が
  「押下毎 1 回」正常(二重発火なし)。

**学び**: vkey patch は未コミットなので CI/release ファームには乗らない → 実機検証は必ず
**ローカル `build-zmk.sh` 産の UF2 を dongle に焼く**こと。chord も Info.plist 埋め込みのため
`swift build` 生バイナリ不可、**`package.sh` のバンドル**必須。

**本番 migration スライス検証 (2026-06-18, 実機成立)**: T_LL_LAYER の 2 キーで移行パターンを実証。
canon keymap `&ll_kp A`→`&vkey 0x1A` / `&ll_kp Y`→`&vkey 0x15`(id=`0x10+n`, A:n=10, Y:n=5)。
chord live config に `[[vkey]] id=0x1A`→ULTRA_LL+a の実アクション(AltTab all-spaces)忠実移植 /
`id=0x15`→`say Y`。dongle 再ビルド・再フラッシュ後、TU_LL+A→AltTab 起動 / TU_LL+Y→"say Y" を
実機確認。**id ルーティング・実アクション忠実移植の両方が動作**。残りは同型の機械展開。
chord TOML は hex id(`0x15`)受理 OK。

**Phase 6 残**: `docs/non-goals.md` 改訂(IOHIDManager は限定例外と明記)+ README([[vkey]]
構文 + Input Monitoring 手順)。test 用 `[[vkey]] id=42/0x1A/0x15` はローカル config のみ
(chezmoi 未 re-add)=検証後に削除/整理。

**全 migration 時の設計論点(スライスでは未確定)**: (a) chord の `$PREFIX - *` fallback
(undefined feedback)は vkey に wildcard が無い→ id 範囲を個別 binding 化 or fallback 廃止。
(b) X_1/X_2/X_3/X_4(カスタム keycode)の vkey 化。(c) サムキー TU_LL 等を `&mo T_*_LAYER`
へ簡素化(修飾子 hold 不要化)。(d) (層,キー)→id 全表の確定。

---

## Phase 0.5 — fresh main 再検証ゲート (BLOCKING, コードを書く前に)

cache は ZMK main @ `fff185e` (2026-05-25, 約 3 週間前)。**patch の context
行が古い main に依存する**ので、実装前に必ず `./scripts/build-zmk.sh --update`
で最新化し、以下を確認する。崩れていれば patch の anchor を貼り直す。

- [ ] `imprint_dongle` build target が解決し `imprint_dongle.uf2` が出る。
      (shield は **canon ローカル** `boards/shields/imprint_dongle/` に在り、
      `Kconfig.defconfig` で `ZMK_USB=y` / `ZMK_BLE=y` /
      `ZMK_SPLIT_ROLE_CENTRAL=y`。Cyboard PR #7 は upstream 化の話で、ビルド
      には**未マージでも非依存**。← risk audit が「PR #7 未マージ BLOCKER」と
      誤検出したが、cache の Cyboard module 側だけ見て canon の `boards/` を
      見落としていた。実体は canon ローカルに在る)
- [ ] `hid.h` の report-id defines が 0x01/0x02/0x03 のみ → `0x20` 空き継続。
- [ ] `zmk_hid_report_desc[]` が末尾 `};` で閉じ、`#if CONFIG_ZMK_POINTING`
      ブロック境界が不変(= append anchor が有効)。
- [ ] `HID_USAGE_PAGE` が依然 `bSize=1`(16-bit page helper 無し)。
- [ ] `usb_hid.c` の `static zmk_usb_hid_send_report` と
      `usb-hid-prime-on-ready.patch` の hunk が今も当たる(両 patch が同
      ファイルを触るので衝突要確認)。
- [ ] `app/CMakeLists.txt` の central gate `(NOT CONFIG_ZMK_SPLIT) OR
      CONFIG_ZMK_SPLIT_ROLE_CENTRAL` が `hid.c`/`endpoints.c`/behaviors/
      `keymap.c` を包み、`usb_hid.c` は `CONFIG_ZMK_USB` gate のまま。
- [ ] behavior locality `CENTRAL=0`(`.locality` 無指定で central 実行)不変。
- [ ] canon が **HKRO**(`ZMK_HID_REPORT_TYPE` choice の既定が HKRO)継続 →
      keyboard report に影響なし。
- [ ] 上流 ZMK に vendor/raw-HID collection や report id 0x20 を足す PR が
      入っていない(重複/衝突回避)。

---

## Phase 1 — ZMK: descriptor + report 配管 + `&vkey` behavior (canon)

**1 つの patch ファイル `patches/zmk/vkey-report.patch` に集約**する(descriptor
と report struct は同じ `hid.h` を触り、`HID_REPORT_ID(0x20)` と struct の
`report_id` が compile 時に一致する必要があるため。build-zmk.sh は
`LC_ALL=C` 順で適用するので分割は部分適用リスク)。新規ファイルは
`--- /dev/null` 形式の diff で同 patch 内に入れる(`git apply` が作成対応)。

ZMK 改変(cache の行番号。fresh main で要再確認):

1. **`app/include/zmk/hid.h`**
   - `#define ZMK_HID_REPORT_ID_VKEY 0x20`(:78 付近)
   - report struct(**named-body 形に統一**):
     ```c
     struct zmk_hid_vkey_report_body { uint8_t id; } __packed;
     struct zmk_hid_vkey_report { uint8_t report_id; struct zmk_hid_vkey_report_body body; } __packed;
     ```
     (:309-312 の consumer struct 隣)
   - decl: `int zmk_hid_vkey_set(uint8_t id);` / `void zmk_hid_vkey_clear(void);`
     / `struct zmk_hid_vkey_report *zmk_hid_get_vkey_report(void);`
   - **descriptor 23 byte を末尾 append**(上記「検証済みbytes」)
2. **`app/src/hid.c`**: `static struct zmk_hid_vkey_report vkey_report =
   {.report_id = ZMK_HID_REPORT_ID_VKEY, .body = {.id = 0}};` + set/clear/get
   実装(:18-19 / :331-333 / :473 隣)。
3. **`app/src/usb_hid.c`**: `zmk_usb_hid_send_vkey_report(void)` を
   **patched `static zmk_usb_hid_send_report` より後**に定義(でないと
   未定義 static 参照でコンパイル不可)。中身は consumer 送信と同型で
   `zmk_usb_hid_send_report((uint8_t*)report, sizeof(*report))`。これにより
   `usb-hid-prime-on-ready` の resume queue を**自動で継承**(2 byte は
   `PENDING_REPORT_MAX_LEN=16` に収まる)。**`get_report_cb` の INPUT switch に
   `case 0x20` を追加**(host の GET_REPORT で default `-EINVAL` ログを避ける。
   低リスクなので入れる)。`app/include/zmk/usb_hid.h` に decl 追加。
4. **`app/src/endpoints.c`**: 専用 `int zmk_endpoint_send_vkey_report(void)`
   (usage_page dispatch の `zmk_endpoint_send_report` は触らない)。USB 分岐は
   実装、**BLE 分岐は `LOG_WRN` + `-ENOTSUP`**(HOG descope。`zmk_hog_send_*` は
   作らない)。**`zmk_endpoint_clear_reports` で vkey も clear+再送(必須)** —
   endpoint 切替/リセット時に host 側 vkey が握りっぱなしになる穴を塞ぐ。
   `app/include/zmk/endpoints.h` に decl 追加。
5. **新規 `app/src/behaviors/behavior_vkey.c`**: `behavior_key_press.c` を範に
   した one-param behavior。ただし event を raise せず**直接** press:
   `zmk_hid_vkey_set(param1 & 0xFF); zmk_endpoint_send_vkey_report();`、release:
   `zmk_hid_vkey_clear(); zmk_endpoint_send_vkey_report();`。共に
   `ZMK_BEHAVIOR_OPAQUE` を返す。
   - 直接呼ぶ理由: behavior は central(ドングル)で実行され、`hid.c`/
     `endpoints.c`/`usb_hid.c` も central に co-located。keycode event 経路
     (`hid_listener` → `zmk_hid_press`)は KEY/CONSUMER page しか扱わず、vendor
     selector には不適。
   - metadata(`BEHAVIOR_PARAMETER_VALUE_TYPE_*`)は ZMK Studio 用。raw 1..255
     なので `..._VALUE`/`..._RANGE` 系を fresh main で要確認、不要なら gate して
     省略可。
6. **新規 `app/dts/bindings/behaviors/zmk,behavior-vkey.yaml`**: `compatible:
   "zmk,behavior-vkey"` / `include: one_param.yaml`。
7. **`app/CMakeLists.txt`**: central gate **内**に
   `target_sources_ifdef(CONFIG_ZMK_BEHAVIOR_VKEY app PRIVATE
   src/behaviors/behavior_vkey.c)`(peripheral では hid/endpoint symbol が無い
   ので gate 外に置くと link 不可)。
8. **`app/Kconfig.behaviors`**: `config ZMK_BEHAVIOR_VKEY` / `bool` /
   `default y` / `depends on DT_HAS_ZMK_BEHAVIOR_VKEY_ENABLED`。
9. **`patches/zmk/README.md`**: `### vkey-report.patch` 節を**同 PR で**追記
   (repo ルール)。upstream 化方針も書く。

canon config 側(patch ではなく通常コミット):

10. **`config/imprint_behaviors.dtsi`**: `behaviors{}` 内に
    `vkey: vkey { compatible = "zmk,behavior-vkey"; #binding-cells = <1>; };`。
11. **`config/imprint.keymap`**: テスト用に空き `&none` を `&vkey 42` に
    差し替え(例: FUNCTION_LAYER。:79 付近)。

### Phase 1G 検証ゲート (ビルド)

- [ ] `./scripts/build-zmk.sh` が 3 target(imprint_left / imprint_right /
      imprint_dongle)を全てビルド成功。
- [ ] 2 回目実行で patch が冪等(reverse-check skip)。
- [ ] dongle `.config` に `CONFIG_ZMK_BEHAVIOR_VKEY=y`。
- [ ] peripheral(left/right, `SPLIT_ROLE_CENTRAL=n`)は `behavior_vkey.c`/
      `hid.c`/`endpoints.c` を**コンパイルせず**かつ clean ビルド(central gate)。
- [ ] dts が `vkey:` node を解決(unknown-compatible エラー無し)。

---

## Phase 2 — 実機 USB raw report 観測ゲート (鉄則。chord 着手の前提)

ドングルを焼いて PC(macOS)で確認する。**ここが通るまで chord (Phase 4+) に
着手しない**(指示書「実装順序の鉄則」)。

- [ ] USB HID descriptor dump(`ioreg -l` / `hidutil`、または Linux
      `usbhid-dump`)で末尾 23 byte が**完全一致**、parser 警告ゼロ。
- [ ] **既存 collection が byte 同一**: 0x01 keyboard(HKRO)/ 0x02 consumer /
      0x03 mouse が patch 前と不変。
- [ ] `ioreg` / IORegistryExplorer に usage page `0xFF31` の新規 top-level
      collection が見える。
- [ ] `&vkey 42` 押下で press 時 2 byte、release 時 2 byte が出る。
- [ ] **(chord にとって load-bearing) numbered report の wire 形を確定**:
      macOS は numbered report の先頭 Report ID byte を剥がして callback の
      `reportID` 引数で渡す。よって `report[0]` は **selector**(`0x2A`)で
      `reportID == 0x20` のはず。実機 dump でこの 1 事実を**記録**する
      (`report[0]==0x2A`, `reportID==0x20`)。ここが逆だと chord 側 callback が
      全件 off-by-one になる。

---

## Phase 3 — 本番 keymap 配置 (canon)

- [ ] テスト `&vkey 42` を本番の id 割り当てに置換、`vkey:` node 確定。
- [ ] ビルドゲート再実行。canon 側はこれで完了。

---

## Phase 4 — chord: `[[vkey]]` config (Core のみ, IOKit 非依存)

(chord repo。詳細 file:line は当該 repo の現行コードに対するもの)

- [ ] **`Sources/ChordCore/Models.swift`**: 新規値型 `VKeyBinding`
      (`id: UInt8`, `action: Action`, `extraDownActions: [Action]`, `name`,
      …)。`Binding`/`Trigger` は**拡張しない**(vkey は Matcher を通さない)。
      `ChordConfig` に `vkeys: [VKeyBinding]`(init 引数、既定 `[]`)を追加。
      `enum Action` は**そのまま再利用**。
- [ ] **`Sources/ChordCore/Config.swift`**: `parse(_:)` で fallbacks の後・
      `ChordConfig` 構築前に `root["vkey"]?.asArrayOfTables` を処理。`id` を
      1...255 で検証(範囲外は warn+drop)、**`parseAction` を実シグネチャで
      再利用**(`row:section:name:source:sourceLine:actionAliases:suffix:
      required:allowReservedVarNames:warnings:`)し `ParsedAction.extraKeys` を
      `extraDownActions` に載せる。重複 id は first-wins + warn。
- [ ] **`Sources/ChordCore/ConfigSchema/SchemaDescriptor.swift`**:
      `vkeyShape()`(`id` 必須 + action-union)+ `sections` に `vkey` の
      `arrayOfTables` を追加。この 1 箇所が JSON Schema 出力と #52 unknown-key
      検証の両方を駆動。
- [ ] **`config.schema.json`**: **手編集せず** `chord config --emit-schema` で
      再生成(additive diff を確認)。
- [ ] **`QuerySchema.swift`** は変更不要(vkey fire は既存 `recordFire` ring に
      流れる)。
- [ ] undefined id は `Log.debug` + no-op。

### Phase 4 検証ゲート

- [ ] `swift test` green + 新規 ChordCoreTests(`[[vkey]] id=1 action-keys` が
      `cfg.vkeys.count==1` に parse)。
- [ ] `chord config --emit-schema | diff - config.schema.json` が空。
- [ ] `chord config --validate` が範囲外 id / `[[vkey]]` 内 unknown key で
      crash せず warn。

---

## Phase 5 — chord: VKeyHIDSource (IOHIDManager) + 配線 + 権限

- [ ] **新規 `Sources/ChordAdapterMacOS/VKeyHIDSource.swift`**: IOHIDManager。
      **`EventSource` には conform しない**(vendor report は OS が tap に
      渡さないので consume/passthrough の返値が無意味)。match dict
      `{UsagePage:0xFF31, Usage:0x01}` → `IOHIDManagerRegisterDeviceMatching
      Callback` → per-device `IOHIDDeviceRegisterInputReportCallback`。callback
      で `reportID==0x20` & `len>=1` を確認し `report[0]`(selector)を closure
      へ。`CFRunLoopGetMain()` + commonModes で schedule。`EventTap.swift` の
      Unmanaged/refcon idiom を範に。
- [ ] **edge 検出は Controller(ChordApp)側**: source は raw byte を surface、
      Controller が `lastVKeyDown` で「press 毎に 1 回」。`0`=latch クリア、
      同 id 連続(autorepeat)は 0 を見るまで無視。lookup → 既存
      `fireBindingAction`(setVariable/toggleVariable interception 込み)で
      dispatch + `recordFire`。
- [ ] **`Package.swift`**: `ChordAdapterMacOS` に
      `linkerSettings: [.linkedFramework("IOKit")]`。
- [ ] **TCC Input Monitoring**(`kTCCServiceListenEvent`)= Accessibility とは
      **別の grant**。未許可だと IOHIDManager は open しても callback が**無言で
      来ない**。`Info.plist` に `NSInputMonitoringUsageDescription`、
      `Permissions.swift` に check/prompt、`config --doctor` に表示、
      `IOHIDManagerOpen` の戻り値をログ。署名 identity(`setup-signing-cert.sh`)が
      新 grant も保持する点を確認。
- [ ] Controller `start()/stop()/loadConfig` に `vkeySource` を配線(CGEventTap
      経路と並走、回帰なし)。

### Phase 5 検証ゲート

- [x] IOKit link 込み `swift build` 成功(ローカル `swift build` clean。IOKit は暗黙
      リンクで `.linkedFramework` 不要だった。macos-15 CI は push 時に確認)。
- [x] daemon 起動で `IOHIDManagerOpen` の成否(Input Monitoring 許可/拒否)を
      ログ(`VKeyHIDSource.start` で成功/失敗とも `Log.line`。実観測は Phase 6)。

---

## Phase 6 — chord: 実機 end-to-end + docs 改訂

- [ ] Input Monitoring 許可下で実 `&vkey` 押下 → `chord query --recent-fires`
      に **press 毎 1 件**。release 後の再押下で再発火。autorepeat(0 無し同 id)は
      非発火。undefined id は debug no-op。
- [ ] 通常タイピングに回帰なし(vendor collection は keyboard stack 不可視、
      exclusive-open もしない)。
- [ ] Input Monitoring 拒否時、無言死せずログが出る。
- [ ] **`docs/non-goals.md` を改訂**(現状「IOHIDManager 不使用」を USP として
      謳っている)。本機能は**意図的な限定例外**(単一 vendor page `0xFF31`、
      自前の 1 byte selector のみ読む。汎用 HID 傍受でも per-device routing でも
      DriverKit でもない)と明記。
- [ ] **`README` に `[[vkey]]` 構文例 + Input Monitoring 手順**を追記。

---

## 未達成 / 保留 (未達成を暗黙にしない)

指示書の受け入れ条件・設計に対し、本計画で**充足しない/先送りする**もの。
将来着手する場合の足がかりも併記。

1. **BLE-HOG 直結での vkey(指示書 受け入れ条件 #2/#6「USB と BLE 両方」)**
   — **未達成(保留)**。現行 canon に HOG を PC へ提示する build target が無い
   (半分は `SPLIT_ROLE_CENTRAL=n` peripheral)。descriptor は共有なので vendor
   collection は HOG の report map(`hog.c`)にも**載る**が、**送信経路が無い**。
   将来着手 = `zmk_hog_send_vkey_report`(新 GATT characteristic + CCC +
   report-ref + msgq + `hog_svc.attrs[N]` index 計算)+ HOG-to-PC build target。
   `hog.c` の hardcoded attrs index が最も脆い部分。
2. **同時複数 vkey** — **未対応(設計上の制約)**。1 byte selector は同時 1 ID
   のみ(`0`=解放, `1..255`=単一 ID)。2 個同時押しは表現不可。upgrade path =
   bitmap report(Report Size 1 × Count N、NKRO collection と同型)。0x20
   collection は独立なので後から拡張可能。
3. **queue-full で press 欠落** — **既知の劣化(許容)**。`usb-hid-prime-on-ready`
   の queue(depth 8、満杯で最古を drop)が suspend/resume burst 中に vkey press
   を捨て release(0)だけ残ると、chord が id を見ず無発火。keyboard report と
   同クラスの劣化。許容して文書化、または 0x20 press を never-drop 特例化。
4. **config.schema.json drift CI guard(chord)** — **未整備**。chord CI に schema
   差分チェックが無く、descriptor 変更で schema.json が stale でも CI は落ちない。
   同 PR で `chord config --emit-schema | diff - config.schema.json` の step 追加を
   推奨(さもなくば手動再生成規律のリスクを明文化)。
5. **daemon upgrade 時の Input Monitoring grant** — **要運用手当**。既存
   daily-driver install は upgrade で新 TCC を自動取得しない。`daemon --resign` /
   署名フローで `kTCCServiceListenEvent` を確実に取得させる手順が必要。
6. **vkey の ZMK 上流化（理想の到達点。任意・long-game）** — **未着手（doc 化のみ）**。
   現方式は ZMK コアへの out-of-tree patch（`patches/zmk/vkey-report.patch`）必須で、その代償が
   ① ZMK main drift で patch anchor が剥がれ得る ② CI が公式 reusable を使えず自前ジョブ（案1）に
   なる、の保守コスト（既存 2 patch と同クラス、apply 失敗で即検知）。**理想の最終形は vkey を ZMK
   本体へ upstream すること**: 採用されれば patch を撤去し CI を公式 reusable へ戻せ、保守コストが
   ゼロになる。**patch（`vkey-report.patch`）は `zmk/app` に対する git diff そのもの＝ほぼそのまま
   upstream PR の素材**。「patch か upstream か」ではなく「**patch で今動かしつつ、汎用化した同じ
   diff を upstream に出す**」関係（patch=橋、upstream=到達点）。着手時の要件: 採用見込みを上げる
   ため canon 固有のハードコード（usage page `0xFF31` / report id `0x20` / 1 byte selector）を
   **設定可能な汎用 vendor/raw-HID behavior** へ一般化する設計が要る（ベンダー固定値のままでは
   upstream 採用は薄い）。**自己完結 module（`badjeff/zmk-hid-io` 系で別 USB HID インターフェース化）
   は別アーキ**で、コア無改変だが USB 専用（BLE 非対応）・3rd-party 依存増・wire 変更で chord 作り直し
   ＋実機再検証が要るため、検証済みの現方式を捨てる価値は薄い（採用しない方針）。判断の経緯は本書冒頭
   「アーキテクチャ判断」と Phase 0 を参照。

## 学んだ詰まりどころ / 注意 (忘れないよう)

- `HID_USAGE_PAGE()` は `bSize=1` 固定。16-bit page は raw long item
  `0x06,lo,hi` でベタ書き(コンパイル検証済。`HID_USAGE_FIDO 0xF1D0` でも同
  truncation を確認)。
- Logical Maximum は符号付き。8-bit `0xFF` は -1。`0x26,0xFF,0x00` を使う。
- Input は値フィールドなら `0x02`(Variable)。`0x00`(Array)は Usage Min/Max
  テーブル前提で誤り。
- descriptor + report struct + report-id は**同一 patch**に。build-zmk.sh は
  `LC_ALL=C` 順適用なので分割は部分適用の危険。
- behavior の `target_sources_ifdef` は central gate の**内側**に置く
  (peripheral で hid/endpoint symbol 不在 → link 不可)。
- `usb_hid.c` を `usb-hid-prime-on-ready.patch` と vkey patch の**両方**が触る。
  hunk 行域の非重複を fresh main で確認。新 send-fn は patched static fn の後。
- chord: macOS は numbered report の Report ID byte を剥がす → `report[0]` は
  selector、`reportID` 引数が `0x20`。Phase 2 実機で必ず確定。
- risk audit の「imprint_dongle 不在 BLOCKER」は**誤検出**(cache の Cyboard
  module だけ見て canon ローカル `boards/shields/imprint_dongle/` を見落とし)。
  実体は canon ローカルに在り `ZMK_USB=y`/`SPLIT_ROLE_CENTRAL=y`。PR #7 は
  upstream 化で、ビルド非依存。

## 本番 migration: 4 層 + X_1 → vkey (確定スコープ)

ユーザー確定: 「**4 層の全キー + X_1**」を vkey 化（**機械的書き換え**、Claude が対応）。
目的は修飾子 soup の全廃。実機リスク低減のため LL 層で 1 周検証 → LM/RM/RR へ横展開。

**現行（修飾子コンボで論理層を表現）→ vkey 化の対応:**

| 層 | サムキー(現) | 現キー macro | 現 chord prefix (input-alias) |
|---|---|---|---|
| T_LL | `TU_LL=&t_ll_ctrl`(層+LCtrl hold) | `ll_kp X`=LCTRL+RALT+RSHIFT+RCTRL+X | `ULTRA_LL="rctrl+ralt+rshift"` |
| T_LM | `TU_LM=&t_lm_alt`(層+LAlt hold) | `lm_kp X`=LALT+RGUI+RSHIFT+RCTRL+X | `MIRACLE_LM="rctrl+rcmd+rshift"` |
| T_RM | `TU_RM=&mo T_RM_LAYER` | `rm_kp X`=RGUI+RALT+RCTRL+X | `MEGA_RM="rctrl+rcmd+ralt"` |
| T_RR | `TU_RR=&mo T_RR_LAYER` | `rr_kp X`=RGUI+RALT+RSHIFT+X | `WONDER_RR="rcmd+ralt+rshift"` |

vkey 化後:
- **canon keymap**: `ll_kp X` → `&vkey <id(LL,X)>`(他層同様)。サムキー `TU_LL/TU_LM` は
  修飾子 hold 不要になり `&mo T_*_LAYER` へ簡素化可。`&kp X_1`(=KP_N1, DEFAULT 層) も vkey 化。
  実装案: `CHORD_KP*` マクロ群(`config/macros.dtsi`)を vkey 送出版に差し替えるか、各層
  bindings を `&vkey N` 直書きに展開。
- **chord 本番設定**: `input = "$ULTRA_LL - c"` → `[[vkey]] id = <id(LL,c)>`(action 同一)。
  `[input-aliases]` の ULTRA_LL/MIRACLE_LM/MEGA_RM/WONDER_RR、`$PREFIX - *` fallback、
  `$ULTRA_LL - j` の `[[sequence]]` も vkey へ移植。
- 現行実バインド(真設定): ULTRA_LL に c/v/d/f/a/s/j(+k,l seq)、各 prefix の `*` fallback。

**id 割当て案（実行セッションで確定）:** 層ごとに base を分けキー位置 n(QWERTY 順 0..29)を加算:
`LL=0x10+n / LM=0x30+n / RM=0x50+n / RR=0x70+n / X_1=0x01`。255 に収まり高 nibble=層で可読。
keymap のキー順を確定して (層,キー)→id 表を作ること。

**本番設定の所在（重要・chezmoi）:** 真の chord 設定は dotfiles
`chezmoi/dot_config/chord/private_config.toml`（plain TOML、template 無し）。運用は
ファイル冒頭明記どおり「`~/.config/chord/config.toml` を直接編集 → `chezmoi re-add`」。
**最終 PR 先: dotfiles repo(設定) + chord repo(アプリ) + canon(keymap/patch)。**

## 引き継ぎ (次セッション開始点)

**完了・検証済:**
- canon firmware **Phase 0–2 ✅**: `patches/zmk/vkey-report.patch` + README + `config/
  imprint_behaviors.dtsi`(vkey node) + `config/imprint.keymap`(テスト `&vkey 42`)。実機
  Phase 2 通過(wire=`[0x20,selector]`, selector=`report[1]`, dongle VID/PID `0x1d50/0x615e`)。
- chord **Phase 4 ✅**: `VKeyBinding` + `[[vkey]]` parse(Config.swift) + `vkeyShape`
  (SchemaDescriptor) + `config.schema.json` 再生成 + `Tests/ChordCoreTests/VKeyTests.swift`。
  `swift build` OK + binary 実証。`swift test` は要 full Xcode(ローカル CLT のみ=不可)→CI。

**chord Phase 5 ✅(完了・未コミット)**: 上記「実装ログ Phase 5」参照。`VKeyHIDSource.swift`
(IOHIDManager, VID/PID `0x1d50/0x615e`, `reportID==0x20`, selector=`report[1]`)+ Controller
配線 + ActionDispatcher/Permissions/Main/QuerySchema/QueryServer + Info.plist×2。`swift build`
clean、敵対的レビュー 4 件全修正。**`Package.swift` の IOKit 明示リンクは不要だった**(macOS
SDK で `import IOKit.hid` は暗黙リンク。元計画の `.linkedFramework("IOKit")` は誤前提)。
**callback は main run loop**(`CFRunLoopGetCurrent()`=`@MainActor start` から=main、
`CFRunLoopGetMain()` ではなく current だが等価)。

**未実装（次セッションの主作業）:**
- **chord Phase 6**: 実機 e2e(&vkey 押下→action 発火、`chord query --recent-fires` に press 毎
  1 件。release 後の再押下で再発火、autorepeat 非発火、undefined id は debug no-op)。**実 daemon は
  packaged `Chord.app` で起動が必須**(`swift build` のバイナリは Info.plist 非埋め込み=Input
  Monitoring が surface しない。`./package.sh` でバンドル化 → 署名 → Input Monitoring 付与 →
  `IOHIDManagerOpen` 成否ログ確認)。`docs/non-goals.md` 改訂(IOHIDManager は限定例外と明記)+
  README([[vkey]] 構文 + Input Monitoring 手順)。ユーザーは Phase 2 で**ターミナルに** Input
  Monitoring 付与済だが **chord.app は別 identity = 別 grant が必要**。
- **本番 migration**: 上記「4 層 + X_1 → vkey」を canon keymap + dotfiles 設定へ機械適用。

**Phase 4 の保留ギャップ（検査系のみ・機能影響なし）:** `config --show --json` が vkeys 非出力 /
`config --validate` サマリに vkey 数なし / vkey 警告の JSON `section` が `[[bindings]]` 誤表示。

**未コミット**: canon(patch/docs/config) + chord(Phase 4: Models/Config/SchemaDescriptor/
config.schema.json/VKeyTests ＋ **Phase 5**: VKeyHIDSource.swift/Controller.swift/
ActionDispatcher.swift/Permissions.swift/Main.swift/QuerySchema.swift/QueryServer.swift/
Info.plist・Info.plist.dev)。コミット・各 PR は指示待ち。

## 参考

- 設計の素: 指示書 `~/Downloads/vkey-vendor-hid-spec.md`。
- ZMK HID 実体: `app/include/zmk/hid.h`, `app/src/hid.c`, `app/src/usb_hid.c`,
  `app/src/hog.c`, `app/src/endpoints.c`, behaviors。
- patch 機構: [`patches/zmk/README.md`](../patches/zmk/README.md),
  [`scripts/build-zmk.sh`](../scripts/build-zmk.sh)。
- dongle 構成: [`docs/dongle-roadmap.md`](dongle-roadmap.md),
  Cyboard zmk-keyboards PR #7(`imprint_dongle` 上流化)。
- chord 側: 別 repo [`chord`](https://github.com/akira-toriyama/chord)
  (`Sources/ChordCore`, `Sources/ChordAdapterMacOS`, `Sources/ChordApp`)。
