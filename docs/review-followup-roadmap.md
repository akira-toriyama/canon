# 0ベース見直し フォローアップ Roadmap

> 2026-06-18 に実施した **canon + chord 0ベース全面レビュー**（14サブシステム /
> 82エージェント / 「マップ→0ベース批評→敵対的検証」）で確定した指摘を、
> **セッションまたぎ**で潰すための単一台帳。
>
> **大原則: 未達成を暗黙にしない。** 着手・完了・棚上げは必ずこのファイルへ反映する。
> 落とした項目は「Backlog (low/nit)」へ移し、消さない。
>
> cross-repo 運用は [refactor-roadmap.md](refactor-roadmap.md) と同じ:
> **chord のコード変更は chord repo の独立 PR**、**本ファイルの更新は canon repo**。
>
> **別系統の進行 workstream**: [ist-roadmap.md](ist-roadmap.md)（zmk-mouse=IST トラックボール
> 受信ドングルを canon へ統合 + ist で vkey）。**C6(docs ドリフト) は ist I1 と同じ canon docs を
> 触るので協調／一括**、**C5(dongle required check) は ist I3 と同じ ruleset 変更なので batch** が効く。

## 進め方 / 検証

- **chord 先行**。順序: **C1 → C2 → C3 → C4**。**chord は C1–C4 すべて ✅ 完了**
  （C3 = vkey#1 + runtime#2 とも完了）。canon は **C5/C6/C7 ✅ 完了**（C5/C6 は ist 統合作業 I1/I3 と
  統合して回収、C7 は build-zmk.sh --reset 実装）。**= 0ベース review follow-up 本体は全完了**
  （残は Backlog の low/nit のみ・任意）。
- 1クラスタ = 1 PR（小さく）。コミットは gitmoji + Conventional Commits。
- 検証コマンド:
  - chord: `cd <chord> && swift build && swift test`（特定は `swift test --filter <Name>`）。
  - canon docs: 目視 + 該当 `verify-*` / `draw` / `commit-lint`。
- 方針順守: 低依存（chord は stdlib/Foundation のみ、新依存追加しない）、無料CI のみ
  （課金 API を CI に足さない）、生成物は手編集しない、README は user 主体で最小訂正。
- レビュー全文（このセッションの transcript・ephemeral）:
  `tasks/wcwtgvgb1.output`。要点は本ファイルへ転記済なので、無くても再開可能。

## ステータス台帳

| ID | 内容 | repo | 優先(検証後) | 状態 | PR |
|----|------|------|------|------|----|
| C1 | 出力 wire-schema 復旧 + 検証テスト | chord | High×4 | ✅ 完了 | [chord#110](https://github.com/akira-toriyama/chord/pull/110) |
| C2 | dry-run / reload renderer 取りこぼし修正 | chord | High + Med×3 | ✅ 完了 | [chord#111](https://github.com/akira-toriyama/chord/pull/111) |
| C3 | ホットパス（handleVKey / Controller spine）テスト | chord | High + Med | ✅ 完了（vkey#1 + runtime#2） | [#112](https://github.com/akira-toriyama/chord/pull/112) / [#114](https://github.com/akira-toriyama/chord/pull/114) |
| C4 | 個別 Medium バグ（exclude_apps / typo section） | chord | Med×2 | ✅ 完了 | [chord#113](https://github.com/akira-toriyama/chord/pull/113) |
| C5 | dongle ビルドを必須チェックへ | canon | High | ✅ 完了（ist **I3** と統合） | ruleset 16483994 |
| C6 | docs ドリフト一括修正（dongle / release / zmk-build / vkey） | canon | Med | ✅ 完了（I1 #74 / I1-tail #78 + 本 reconcile PR） | – |
| C7 | flash-reset.sh dead path 解消（削除 or 実装） | canon | Med | ✅ 完了（実装・user GO） | [canon#85](https://github.com/akira-toriyama/canon/pull/85) |
| BL | Backlog（low/nit 多数） | both | Low/nit | ☐ 未着手 | – |

状態記号: ☐ TODO / ▶ 進行中 / ✅ 完了(PRリンク) / ⏸ 棚上げ(理由必須)。

---

# chord（先行）

## C1. 出力 wire-schema 復旧 + 検証テスト　[High・最優先]

**問題（実害最大）**: `chord config --show --json` の契約 `docs/schema/chord.bindings.v3.json`
が、実エミッタ `Sources/ChordCore/Schema.swift`（`WireBinding`/`wireAction`/`wireCondition`）
の出力を**拒否**する。`binding` が `additionalProperties:false` なのに schema が以下を未定義:

1. `binding`: `passthrough`(bool) / `repeat`(enum) / `input_source`(array of string) が無い。
2. `$defs/action` の oneOf に `kind:"toggle-variable"` が無い（emit: `Models.swift` kindString /
   `Schema.swift` wireAction）。
3. `$defs/condition` が `variable` 単体で、`kind:"all"`（2件以上の `when-vars` AND ゲート、
   emit: wireCondition の `.conjunction`）を表現できない。

→ これらの機能を使う config ほど出力が**自分の契約スキーマで validation 失敗**。
CLAUDE.md(chord) は「wire を変えたら Schema.swift と schema を同一コミットで」と規定するが、
**出力 JSON を検証するテストが無い**ため #45/#46/#47 で静かにドリフトした（根本原因）。

**変更（すべて前方互換の追加 = v4 bump 不要）**:
- `docs/schema/chord.bindings.v3.json`
  - `$defs/binding.properties` に `passthrough`/`repeat`(enum: `ignore`,`passthrough`)/`input_source`。
  - `$defs/action` に 5本目の oneOf: `kind` const `toggle-variable`, required `[kind, variable]`,
    `variable` `{type:string, minLength:1}`, 任意 `raw`（set-variable 枝に倣う）。
  - `$defs/condition` を oneOf 化: 枝1=既存 `variable`、枝2=`kind` const `all` +
    `conditions:{type:array, items:{$ref:"#/$defs/condition"}}`（再帰）。
- `Sources/ChordCore/Schema.swift` / `Models.swift` 側は emit 済なので原則変更不要
  （実行時に現在行を再確認すること）。
- `docs/glossary.md`(chord) §1 Condition（~137-139）の「conjunction は future/#19」記述を
  出荷済（`all`）へ更新。

**テスト（新規・lockstep を honor-system → 決定的に）**:
- `Tests/ChordCoreTests/WireSchemaValidationTests.swift`（新規, ChordCoreTests）。
- passthrough + repeat + input_source + toggle-variable + 2件 when-vars(kind=all) + vkey を
  盛った Config を作り、ChordCore の wire emit 経路で JSON 化（`JSONSerialization`）。
- `docs/schema/chord.bindings.v3.json` を読み、各 `$def` の `additionalProperties:false`
  プロパティ集合と enum/const に、出力の全キー/kind を照合（**フル JSON-Schema ライブラリは使わず**
  Foundation のみ。`ConfigSchemaDriftTests` が入力スキーマで同種の on-disk 読みをしている=前例あり）。

**Done-when**: 新テストが **schema 修正前は FAIL / 修正後は PASS**。`swift test` green。
以後 wire フィールド追加で schema を忘れると CI で即死する。

**実施メモ（✅ chord#110）**:
- 3点の元票に加え、whole-doc 検証（「出力の全キー」照合）が **4点目のドリフト
  `$defs/options.fn_auto_arrows`**（全 `--show` 出力に常在）を surface → 同 PR で修正。
- emit は先行済のため `Schema.swift`/`Models.swift` は無変更。schema(+test+glossary) のみ。
- ローカル toolchain（CLT）は XCTest 非搭載 → 実 ChordCore emit + 同一 validator の
  standalone driver で **FAIL（`$.bindings[0].repeat`）→ PASS** を機械検証（driver 未コミット、
  本体 XCTest は CI macos-15 で実行）。
- 敵対的検証（4-agent workflow）verdict = **GO / MUST_FIX なし**。検出した既存 gap は
  下記 Backlog「C1 follow-up」へ退避（本 PR の config では発火しない別クラス）。

---

## C2. dry-run / reload renderer の取りこぼし修正　[High + Med]

**問題**: `daemon --reload --dry-run`（適用前プレビュー）が、後から増えた config 次元を黙って落とす。

- **[High] cli#1**: `[input-aliases]` 変更が**一切描画されない**のに `isClean` は false →
  「全0の空 diff」を見せて嘘をつく。`Sources/ChordApp/ReloadDiffPrinter.swift:49-95`
  （printReloadDiff）に input-aliases 枝が無い。diff 層(`Schema.swift` BindingsSchema.diff)は対応済。
- **[Med] cli#4**: `Sources/ChordCore/Schema.swift:406-417`(semanticallyEqual) が
  `passthrough`/`repeatStrategy`/`inputSource` を比較しない → これらだけ変えた編集が「変更なし」と誤報告。
- **[Low] cli#2**: `describe()`（ReloadDiffPrinter, ChordApp）が set-variable/toggle-variable の
  `name=value` を落とす（`config --show` は出すのに不一致）。
- **[Low] cli#3**: changed-binding 描画(printDiffBucket 118-140)が condition/hold_while/
  hold_while_timeout/action_on_up を出さず `~ <name>` だけ → 「何が変わったか言えない」。

**変更**:
- `Sources/ChordApp/ReloadDiffPrinter.swift`:
  - printReloadDiff に input-aliases バケット追加（action-aliases ブロック ~79-94 に倣う,
    `diff.inputAliasesAdded/Removed/Changed` 駆動）。
  - describe() に set-variable/toggle-variable ケース追加（`action.variable`/`action.value`、
    `config --show` の文言に合わせる）。
  - printDiffBucket changed ループに condition/holdWhile/holdWhileTimeoutMs/actionOnUp 分岐追加。
- `Sources/ChordCore/Schema.swift` semanticallyEqual に
  `&& a.passthrough==b.passthrough && a.repeatStrategy==b.repeatStrategy && a.inputSource==b.inputSource`。

**テスト**:
- semanticallyEqual: `Tests/ChordCoreTests/DiffTests.swift`（ChordCore 側）にフィールド別ケース。
- renderer/describe: **ChordIntegrationTests**（describe()/printReloadDiff は ChordApp private なので
  `@testable import ChordApp` 必須。ChordCoreTests には置けない）。
- 「semanticallyEqual が見る全フィールド ⇔ renderer の全行 ⇔ WireBinding の保持フィールド」を
  対にする guard test を足し、将来フィールドが落ちないようにする。

**Done-when**: [input-aliases]-only / passthrough-only / condition-only の各編集で
dry-run が**正しい非空 diff** を出す。`swift test` green。

---

## C3. ホットパスのテスト空白を埋める　[High + Med] — ✅ 完了（vkey#1 chord#112 / runtime#2 chord#114）

**進捗（2026-06-19）**: **vkey#1 ✅（chord#112）+ runtime#2 ✅（chord#114）= C3 完了**。

- **vkey#1**: `handleVKey` のエッジ/ラッチ算術を純粋値型 `VKeyEdgeTracker`（ChordCore）へ抽出し、契約 10 ケース
  （dedup / 0=release / A→B roll / **wedge 回帰** ほか）をユニットテスト化。`held` は dispatch/pause と独立に
  前進＝構造的に wedge 不能。挙動不変（敵対的レビュー 3 レンズで等価性確認・correctness バグ 0）。
- **runtime#2**: `Controller.handle` の consume/pass spine を**実 handle() で統合テスト**。`handle()` が
  `nonisolated private` で `@testable` でも届かないため、**`#if DEBUG` テスト seam を新設**
  （`startForTesting(matcher:)` = `resetState()`+`publishMatcher()`+ 実 `start()` と同一 closure で
  `source.start { handle($0) }` を配線、AppKit/AX/IPC 不要 / `variableSnapshotForTesting` /
  `pendingUpCountForTesting`）。production は追加のみ・挙動不変。`ControllerSpineTests` 6 ケース
  （B1 ペアリング / autorepeat 3 戦略を **outcome + 再 fire 副作用**で判別 / on-up / toggleVariable /
  modifier-only entry・exit / passthrough は action 発火・pendingUp 非登録）。standalone driver で実
  `handle()` を seam 経由で全 PASS、敵対的レビュー 3 レンズ = GO。confirmed SHOULD_FIX 1 件（autorepeat が
  outcome のみ assert で ignore/fire-each を判別できず）を同 PR で解消。seam の落とし穴（tap は Controller を
  弱参照 = テストが保持しないと dealloc→無言 passthrough）を `live` 配列で解消。**残（out of scope）**は下記 Backlog
  「C3 follow-up」へ。

**問題**: 最も安全性が重要な層に**直接テスト 0**。
- **[High] vkey#1**: `Sources/ChordApp/Controller.swift:362-388`(handleVKey) の
  dedup / 0=release / A→B roll / `lastVKeyDown` ラッチ。**vkey-roadmap の敵対的レビューが
  wedge バグ（pause-中-release でラッチ固着）を見つけた当の箇所**。今は手動 HW 確認のみ。
- **[Med] runtime#2**: `Controller.handle`(67-388) の down/up ペアリング(consume/pass の B1 契約)、
  autorepeat 分岐、on-up、modifier-only 発火、extendTimer 順序。`TestEventSourceTests` は
  本物の Controller でなく**並行再実装**を回しており実コードパス未走。CLAUDE.md が
  「consume/pass spine — DO NOT regress」と名指しする箇所。

**変更（バグ修正でなくテスト可能化）**:
- handleVKey のラッチ/エッジ算術を ChordCore の純粋ヘルパーへ抽出
  （例 `VKeyEdgeTracker.events(for: UInt8) -> [(Trigger, kind)]`、`lastVKeyDown` を所有）。
  bundle/input-source 読みは handleVKey に残し、出力を handle() へ流す。
- spine は副作用なしの薄い test-only 入口を出す（例 `installHandler(on: EventSource)` で
  AppKit/AX/IPC を起こさず handle() を配線、または handle/handleVKey を @testable-internal）。
  seam は既存: `Controller.init(source:)` public + `EventSource` + `ChordAdapterTest` の
  TestEventSource + ChordIntegrationTests は ChordApp link 済。

**テスト**:
- ChordCoreTests: VKeyEdgeTracker の4ケース（初回押下 / 同id dedup / 0=release / A→B roll）
  + pause-中-release 回帰。
- ChordIntegrationTests: 本物の down→up consume（consumed down の後だけ up を consume）、
  vkey A→B roll（A の up が B の down より前にペア）、各 RepeatStrategy を TestEventSource で駆動。

**Done-when**: handleVKey エッジ math と Controller ペアリング/repeat が無料スイートでカバー。
`swift test` green。新依存・課金 CI なし。

---

## C4. 個別 Medium バグ（クラスタ外）　[Med×2] — ✅ 完了（chord#113, 2026-06-19）

両方とも「設定したつもりが静かに効いていない」correctness バグ。1 PR で回収。

- **matcher#1 — exclude_apps バイパス** ✅: `Sources/ChordCore/Matcher.swift`
  (modifierTransitions) が global `excludeApps` を見ない（`find()` は尊重）。
  → globally 無効化したアプリで modifier-only binding（setVariable リーダー / hold-while）が発火。
  **修正**: 関数頭に `find()` と token-for-token 同一のガードを追加。
  `ModifierTransitionsTests.testGlobalExcludeAppsSuppressesTransitions`（exact / glob 除外 + 非除外は entry）。
- **parsing#1 — typo セクションを parser が黙認** ✅: `[[bindigs]]` / `[optoins]` 等が
  `--validate --strict` を 0 通過（エディタ JSON schema の方が厳しい逆転）。
  **修正**: `StructuralCheck.unknownKeyWarnings` に root スキャンを追加し、root キーを
  `Set(ChordConfigSchema.sections.map(\.name))`（TOML.lineKey 除く）に照合して未知を warn。
  **新 Kind は足さず既存 `.unknownKey` を再利用**＝wire schema `dropped[].kind` enum drift を回避。
  メッセージはユーザの構文を反映（`[[x]]`/`[x]`=section、bare scalar `x`=key）。
  `ConfigTests.testUnknownTopLevelSectionWarns` + `testKnownTopLevelSectionsDoNotWarn`。

**実施メモ（✅ chord#113）**:
- 実 ChordCore を standalone driver でリンクし **修正前 5 assertion FAIL → 修正後 全 PASS** を機械検証
  （XCTest は手元 CLT に無く CI 実行）。glossary `unknown-key` 行 + `ConfigWarning` docstring を broaden。
- 敵対的レビュー（4レンズ: `find()` 等価 / 偽陽性・schema drift / 回帰 / 規約）= **GO・confirmed defect 0**。
  検出 NIT 2 件を下記 Backlog「C4 follow-up」へ退避。

---

# canon（後続セッション）

## C5. dongle ビルドを必須チェックへ　[High] — ✅ 完了（ist I3 と統合, 2026-06-19）

dongle（+ ist）ビルドが main 保護 ruleset(id 16483994) の required_status_checks に無く、
壊す PR がマージ可能 → release.yml を壊す既知の障害クラスだった。
**実施（ist I3, user "I3 GO"）**: ruleset 16483994 の required_status_checks に
`build / Build (xiao_ble/nrf52840/zmk, imprint_dongle)` と `(…, ble_hid_host_receiver)` を追加
（C5 が求めた dongle + ist の両方）。これで全 4 製品ビルド + `lint / lint` が必須。**コード変更なし**。
詳細は [ist-roadmap.md](ist-roadmap.md) の I3。

## C6. docs ドリフト一括修正　[Med・doc のみ] — ✅ 完了（I1/#74・I1-tail/#78・本 reconcile PR, 2026-06-19）

**回収状況**: CLAUDE.md（scope/壊しやすい点/build pipeline/release モデル/build target 数）と glossary
（board/shield/build target/.uf2 を dongle+ist 込みへ・vkey 用語追加・mermaid・edge ラベル）は I1/I1-tail
で完了。**残り（README transport「修飾キー chord→v-key」/ README「boards/shields 空が正常」/
commit-convention の release モデル）は本 reconcile PR で修正**。下記は元の指摘リスト（記録用）:
- 「boards/shields は空が正常」→ `boards/shields/imprint_dongle/`(4ファイル)が存在。
  （README×2 / `CLAUDE.md:34` / `docs/glossary.md:140`）→ 「唯一のローカル shield は dongle」と限定。
- 「build target は2つ / shield=left|right」→ 実3つ。`glossary.md`(build target/board/shield/.uf2)
  と `CLAUDE.md:33` を dongle 込みへ。`build.yaml:1` ヘッダコメントも3ターゲットへ。
- 「build.yml は ZMK 公式 reusable」→ 実は patch を当てる canon ローカル `zmk-build.yml` に委譲。
  `CLAUDE.md:78`（+ :40 の「@main」）を更新し zmk-build.yml を inventory へ（背景=vkey-roadmap「案1」）。
- release モデル: 「手動 dispatch → 即 vX.Y.Z タグ」→ 実は push:main 自動 → ローリング draft 更新 →
  手動 Publish で初めてタグ + dongle uf2 添付。`CLAUDE.md` / `README.md:77-82` /
  `docs/commit-convention.md:61-75`（特に「タグを作成・push」の誤記と uf2 一覧へ dongle 追加）。
- transport: 「修飾キー chord を送出」→ vendor-HID v-key へ置換済（同 README 下部と自己矛盾、
  glossary の "Don't call it: chord" 自己違反）。`README.md:6,22` / `README.en.md:6,22` /
  `glossary.md:64` のエッジラベル。
- **glossary に `vkey` 項目が無い**（canon 自身の同一PR規約違反、chord glossary は逆参照済）。
  `### vkey` を「firmware の用語」へ追加（canonical `vkey`、`&vkey <id>`=vendor-HID selector
  usage page 0xFF31 / report ID 0x20、リンク: imprint_behaviors.dtsi / gen-vkey-aliases.py /
  chord glossary §6、`Don't call it: original key, custom keycode`）。
- chord-ci-docs#6: `CLAUDE.md:193`(chord) の `undefined_aliases` → `undefined_action_aliases`
  （※これは chord 側。C6 ではなく chord backlog 扱いでも可）。

README は user 主体 → 最小ファクト訂正のみ、構成変更しない。

## C7. flash-reset.sh dead path 解消　[Med] — ✅ 完了（実装・user GO, 2026-06-19）

`scripts/flash-reset.sh` → `flash-impl.sh` が `firmware/imprint_*_RESET.uf2` を参照するが
**それを生成する build target が存在せず必ず ERROR**だった。選択肢 (a) 削除 / (b) 実装のうち、
**user GO で (b) 実装**（refactor T2 が NVS-destructive 文言を意図的に残した＝機能を欲する意思）。

**実装（option B・I4 の `--logging` と同じローカル flag 方式）**:
- `build-zmk.sh --reset` を新設。選択ターゲットを**実シールド据置**のまま
  `CONFIG_ZMK_SETTINGS_RESET_ON_START=y`（ZMK 標準 settings_reset の本体機構＝SYS_INIT で
  `zmk_settings_erase`）で焼き直し `<shield>_RESET.uf2` を出す。`--logging` と排他。
  **build.yaml/CI/release は不変**（ローカル専用）。
- **gotcha**: シールドごと `settings_reset` に差し替える素朴な方式は不可。assimilator-bt の
  board dts が **imprint シールド由来の `spi1_default` pinctrl を参照**しており、shield 差し替えで
  未定義 → `cmake` が `undefined node label 'spi1_default'` で失敗する。実シールド据置 + reset config
  だけ載せる方式で回避（board-defined keyboard 一般に効く）。
- `flash-reset.sh` ヘッダを実態へ更新（先に `build-zmk.sh imprint --reset` で生成 → flash →
  通常 firmware を焼き直す。reset firmware は**起動毎に**NVS を消す＝working keyboard だが要再 flash）。

**検証**: `shellcheck` clean、`build-zmk.sh imprint --reset` で **3 機種すべて成功**（assimilator-bt 含む）、
`imprint_left_RESET` の `.config` に `CONFIG_ZMK_SETTINGS_RESET_ON_START=y` 在・通常版と差分あり（config 反映確認）。
実機での NVS 消去検証は user（HW 必要）。`--logging`/`--reset` 排他・`--help` 反映済。

---

# Backlog（low/nit・落とさないための保管庫）

着手は任意。触る PR の「ついで」に拾うか、専用 PR で一括。**消さずにここで追跡**。

**chord — C1 follow-up（wire 契約の残り gap・C1 の whole-doc 敵対的検証で発覚）**:
> 5件は **既存**の同クラス契約ドリフト（`--show --json` の一部出力が published schema で拒否される）。
> C1 の kitchen-sink config では発火しない（on-up/extra なし・vkey alias 妥当・dropped 0）ため C1 では未修正。
> **小さな後続 PR 1本で一括**（大半は `dropped[]`/on-up の `raw` 任意化）。WireSchemaValidationTests を拡張して回帰固定。
- c1f#1: action oneOf `keys` 枝 required に `raw` → `action_on_up`/`extra_actions` の keys は
  `raw:nil`（省略）で**拒否**。`raw` を required から外す（任意化、set-/toggle-variable に倣う）。
  schema:`$defs/action` keys 枝 / emit:Schema.swift `wireAction(.keys)`（wire() の on-up/extra 経路）。
- c1f#2: 同 `shell` 枝 required の `raw` → `action-shell-on-up` が `raw:nil` で拒否。`raw` 任意化。
- c1f#3: `dropped.section` enum に `"[v-key-aliases]"` 欠落 → 不正 `[v-key-aliases]` 行
  （name-shadow/非int/範囲外/重複）の warning が section で拒否。enum に追加。emit:Schema.swift:~680。
- c1f#4: `dropped.kind` enum に `"v-key-alias-invalid"` 欠落（ConfigWarning.Kind 唯一の漏れ）→
  同 warning が kind でも拒否。enum に追加（c1f#3 と同 PR）。
- c1f#5: **emitter バグ**: `wireDropped(.actionAliasNonString)` が section に camelCase
  `"[actionAliases]"` を出力（v3 enum はハイフン `"[action-aliases]"`）。Schema.swift:~674 を
  `"[action-aliases]"` へ（schema 側は正しい、emitter を整合）。
- c1f#nit: schema 冒頭 `description` が forward-compat を「v2.x が…」止まりで 0.8/0.9 の追加
  （passthrough/repeat/input_source/fn_auto_arrows/toggle-variable/condition `all`）を未反映。一文追記（任意）。

**chord — C2 follow-up（C2 の敵対的検証で発覚・既存挙動）**:
- c2f#1: reload-diff の changed-loop が input 行を `input.raw` のみで gate（ReloadDiffPrinter.swift）。
  `[input-aliases]`/`[v-key-aliases]` の**本体**変更時、それを参照する binding（raw 不変・解決後 modifier/trigger
  だけ変化）が `~ <name>` だけになる。semanticallyEqual は full WireInput 比較で changed 検出するのに
  理由行が出ない。※ alias バケット自体は実差分を表示するので「空 diff の嘘」ではない（C2 で導入した退行でもない）。
  **修正案**: gate を `c.old.input != c.new.input` にし、raw 不変時は解決後 modifier-set/trigger の delta を描画
  （describeMods を input.modifiers に流用 + trigger.name/keycode）。ReloadDiffRenderTests に
  「[input-aliases] body だけ変えた参照 binding が非 bare 理由を出す」ケース追加。

**chord — C3 follow-up（runtime#2 の敵対的検証で out-of-scope と確定・暗黙に落とさない）**:
- c3f#1: **extendTimer 順序**（handle の B-α reset-on-use）は runtime#2 mandate に挙がるが、global
  `variableStore` の scheduler を test 注入できず現 seam では決定的に観測不可（timing 依存＝flaky 回避）。
  VariableStore 自体は fake scheduler で単体テスト済。seam を「scheduler 注入可」へ拡張すれば取れる → 任意の後続。
- c3f#2: `extraDownActions`（down の Karabiner 風 multi-action）と vkey trigger の handle() ペアリングは未カバー。
  後者は key pairing と構造同一（B1 テストが汎用的に固定）+ `VKeyEdgeTracker` 単体テスト済。前者は `.keys` 発火＝
  実 CGEvent post が要るため value-only seam の範囲外。記録のみ。
- c3f#nit: `isPaused()` 早期 passthrough は到達可能だが pause を flip する seam が無い（1 行の early return・低価値）。

**chord — C4 follow-up（C4 の敵対的検証で発覚・既存挙動／TOML 仕様）**:
- c4f#1: top-level section typo の warning が wire `dropped[].section` で `[[bindings]]` を表示
  （`wireDropped` default ケース。`unknown-option-key` 等と同じ**既存近似**。v3 schema は `section` を
  非権威と明記＝`kind` で分岐し `message` を表示する契約なので validation は通る）。正確化には
  `ConfigWarning` へ section リテラルを保持させる必要 → 小さな後続 PR（emit + WireSchemaValidationTests 拡張）。
- c4f#2: plain-table typo（`[optoins]`）の `sourceLine` は nil（`__line__` は `[[X]]` 行のみ seed の
  TOML 仕様。`[[bindigs]]` は行付き）。graceful・message は section 名提示。ChordCore 内では修正不可
  （upstream swift-toml-edit がテーブルヘッダに行を seed すれば解消）。記録のみ。

**chord low/nit**:
- cli#5: `--help` EXIT CODES が exit1 を過少記述（doctor/watch も1）。Main.swift:670 + README:330。
- packaging#1: Intel Mac で `/opt/homebrew` ハードコード（Resign.swift）→ `brew --prefix` 解決。
- packaging#2: Resign.swift が `--options runtime` 無しで再署名（package.sh は有り）→ 揃える。
- packaging#3: CFBundleVersion が 1 固定 → コメント明記 or package 時に同期。
- packaging#4: setup-signing-cert の重複 collapse が「先頭 keep」→ delete-identity で鍵孤児回避。
- packaging#5: package.sh `--dev` 派生に test/CI guard 無し。
- tests#1: WatchLogTests が稼働中 daemon の `/tmp/chord-watch.log` を消す → `XCTSkipIf(fileExists)`。
- ci-docs#5: config.schema.json が `/bin/sh`、実体は `/bin/zsh -l -c`（SchemaDescriptor.swift:140 + 再生成）。
- ci-docs#6: CLAUDE.md `undefined_aliases` → `undefined_action_aliases`。
- ci-docs#7: CLAUDE.md:856-861 / config.toml:402 の「hand-rolled TOML parser」記述が陳腐化
  （swift-toml-edit 移行済、単一行配列制約は phantom）。
- parsing#2: [input-aliases] が case-folded 重複を黙認（[v-key-aliases] は warn）→ guard を揃える。
- parsing#3: dead な `Int(Int)` cast 6箇所（Config.swift:212 ほか。T5 docstring と矛盾）。
- runtime#3: Controller.swift:68-71 の「lock-free atomic snapshot」コメントが嘘（実は matcherLock）。
- runtime#4: autorepeat 毎 tick の recordFire が recent-fires ring を溢れさせる → `if !event.isRepeat`。
- matcher#2: onUpAction doc(Models.swift:303-306) が `.modifiersOnly` を列挙漏れ。
- vkey#2: A→B vkey roll で release timing が別キーに帰属（firmware 仕様）→ handleVKey doc に1文追記。

**canon low/nit**:
- ~~gen#1: gen-vkey-aliases.py がコメントも走査（将来 `// &vkey 0xNN` で誤爆）→ 行コメント除去。~~
  **✅ 完了（ist I2 #76）**: `strip_comments`（`/* */` と `//` を除去）を両 keymap 走査に追加。
  （ist keymap 冒頭の例ノードを拾わない要件と同時に解決。）
- ~~gen#2: DEFAULT alias `KP_X1` が chord 予約 `kp_*` 名前空間 → `VK_X1` 等へ改名し再生成。~~
  **✅ 完了（[canon#88](https://github.com/akira-toriyama/canon/pull/88)）**: gen-vkey-aliases.py の `KP_X1`
  （変数 `KP_X1_ID` 含む）→ `VK_X1` 一括改名 + `config/vkey-aliases.toml` 再生成（`VK_X1 = 0x01`・--check 通過）+
  vkey-roadmap 採番スペック整合。**chord 追従（残・user）**: imprint vkey は既に chord 稼働中のため live
  `~/.config/chord/config.toml` は現状 `KP_X1`。機能影響なし（id `0x01` で成立・alias 名は人間用ラベル）だが、
  次回 chord 再同期で alias 定義 + 参照 binding を `VK_X1` へ改名要。
- ~~gen#3: PR テンプレに vkey 用チェック欠如（eiji にはある）→ sibling checkbox + verify-vkey-sync 追記。~~
  **✅ 完了（canon#88）**: vkey sibling checkbox + 手編集禁止リストへ `config/vkey-aliases.toml` + CI 列挙へ `verify-vkey-sync`。
- ~~gen#4: eiji `disp:[X]` regex が幅検証なし → 1文字 assert で fail-loud。~~
  **✅ 完了（canon#88）**: MACRO_RE 取り込み時に `len(ch)==1` を検証し違反は SystemExit。正常入力（全 disp 1 文字）は出力不変。
- build#3: build-zmk.sh ↔ zmk-build.yml で patch-apply / west-build / awk が三重複
  （awk 抽出を `scripts/lib/parse-build-targets.sh` へ最初に切る、機会的に）。
  **⏸ 据置（canon#88 で見送り）**: build matrix 生成＝全ビルドのクリティカルパスで blast radius 大・ローカル検証も
  Docker/CI 必須＝drive-by 不可。awk だけでなく patch/west の三重複統合まで含む大きめ refactor として別途意図的に。
  当面は ci#3 の相互参照コメントで同期担保。
- ~~ci#3: 同 awk の相互参照コメントが片方向 → build-zmk.sh 側にも逆参照コメント。~~
  **✅ 完了（canon#88）**: build-zmk.sh の `_build_pairs` に zmk-build.yml への逆参照コメントを追加し双方向化。
- build#2: README が flash-watch.sh / dongle flashing 未記載（C7 解消後に最小追記）。
  **⏸ 据置（user 主体）**: README は user 主体執筆方針（CLAUDE.md）。フラッシュ節の最小文案は用意済で user 承認待ち
  （flash-watch.sh = 左/右/dongle 自動コピー、flash-reset.sh = NVS リセット → dongle-roadmap 参照）。
- ~~keymap#2: `ALL_MODS` dead define（behavior_macros.h:23-24）削除 +
  keymap_drawer.config.yaml:140-142 の陳腐化コメント修正（arrow morph は Ctrl+Alt のみ）。~~
  **✅ 完了（[canon#87](https://github.com/akira-toriyama/canon/pull/87)）**: ledger の 2点に加え、
  実調査で **`special_combinations` `Hyper+`(4mod)/`Meh+`(3mod)（keymap_drawer.config.yaml:155-156）も
  道連れの dead**（3〜4mod を生む binding が repo に不在）と判明 → 3点まとめて削除。いずれも refactor T1
  （`73ea43c`「vkey 移行で孤児化した修飾子 chord 機構を削除」）の掃除し残し。v-key 導入で複雑 MODS が
  不要化した帰結。firmware build / drawer SVG ともに不変（ALL_MODS 未使用・Hyper/Meh 元々未発火）。
- keymap#3: kana/eiji 0-cell wrapper macro の冗長 indirection（任意 de-dup、draw 再実行必須）。
  **⏸ 据置（canon#88 で見送り・知見記録）**: `HOLD_TAP_HP200(ime_kana,&kana)` は `bindings=<&kp>,<&kana>`、
  combo `<&ime_kana MOD KANA>` の KANA(param2) は 0-cell `&kana` に渡らず無視され `kana` macro が内部で
  `&kp KANA` を出す＝確かに冗長。**ただし** `kana`/`eiji` wrapper は keymap-drawer の raw_binding_map
  （`&kana`→かな / `&eiji`→英数）の表示名も担い、素朴な `&kp` 置換は drawer ラベル回帰になる
  （macros.dtsi:34-39 が EN_MACRO 分離を「描画名空間のため意図的」と明記する設計と同種）。de-dup は
  drawer 表示の作り直し込みで別途。

**検証で棄却済（false-positive・対応不要・再提起しないための記録）**:
- 「dongle keymap に vkey node が無い」→ 実ビルド成果物で vkey node 搭載を確認（誤検知）。
- 「clearStale が iterate 中 dict 破壊 = crash」→ Swift COW で安全（実機確認）。
- patch 適用順依存 / 0xFF31 マッチング誤解 / glob 1秒 wall-clock テスト → いずれも棄却。

---

## 更新ログ

- 2026-06-18: 0ベースレビュー実施、本 roadmap 作成（全クラスタ TODO）。chord 先行で着手予定。
- 2026-06-18: **C1 ✅ 完了（chord#110）**。wire-schema を emit 済へ整合（binding 3 + options
  fn_auto_arrows + action toggle-variable + condition oneOf）＋ lockstep テスト新設（FAIL→PASS 検証）。
  敵対的検証 verdict=GO（MUST_FIX 0）。検出した既存 gap 5件+nit を Backlog「C1 follow-up」へ記録。
  次は C2（dry-run / reload renderer 取りこぼし）。
- 2026-06-19: **C2 ✅ 完了（chord#111）**。dry-run/reload renderer の取りこぼし 4 件
  （cli#1 input-aliases 空 diff / cli#4 semanticallyEqual の passthrough・repeat・input-source 比較漏れ /
  cli#2 set・toggle-variable 描画 / cli#3 condition・hold・on-up 理由行）を修正。renderer を String 返却化し
  ReloadDiffRenderTests + WireBindingDiffCoverageTests + DiffTests を新設（CI all green）。
  敵対的検証 verdict=GO（MUST_FIX 0）。1 件の既存 gap を Backlog「C2 follow-up」へ。次は C3。
- 2026-06-19: **canon 側を ist 統合作業の中で回収して reconcile**。**C5 ✅**（ist I3 = ruleset 16483994 に
  dongle + ist build を required 追加）/ **C6 ✅**（CLAUDE.md・glossary は I1/#74・I1-tail/#78、README transport・
  boards-shields・commit-convention の release モデルは reconcile PR #81）/ **Backlog gen#1 ✅**（I2/#76 の
  strip_comments）。canon 残は **C7 のみ**。
- 2026-06-19: **C3 vkey#1 ✅（chord#112）**。`handleVKey` のエッジ/ラッチを純粋 `VKeyEdgeTracker` へ抽出 +
  契約 10 ケースのユニットテスト（wedge 回帰含む）。挙動不変・敵対的レビューで等価性確認。**残 = runtime#2**
  （Controller spine 統合テスト、テスト seam 新設が前提）+ C4 + C7。
- 2026-06-19: **C4 ✅（chord#113）**。matcher#1（`modifierTransitions` に `find()` 等価の exclude_apps
  ガード）+ parsing#1（top-level section typo を `.unknownKey` で警告・新 Kind 無しで wire enum drift 回避）を
  1 PR で回収。standalone driver で FAIL→PASS 機械検証、敵対的レビュー（4レンズ）= GO・defect 0。
  NIT 2 件を Backlog「C4 follow-up」へ。**chord 残 = C3 runtime#2 のみ**、canon 残 = C7。
- 2026-06-19: **C3 runtime#2 ✅（chord#114）= chord C1–C4 完了**。`Controller.handle` の consume/pass spine を
  `#if DEBUG` テスト seam（`startForTesting`）経由で**実 handle() 統合テスト**（`ControllerSpineTests` 6 ケース）。
  production 追加のみ・挙動不変。standalone driver で全 PASS、敵対的レビュー（3レンズ）= GO。confirmed SHOULD_FIX 1 件
  （autorepeat の ignore/fire-each 判別）を同 PR で解消。out-of-scope（extendTimer 順序 ほか）を Backlog「C3 follow-up」へ。
  **canon 残は C7 のみ**（flash-reset dead path・削除前 user 確認）。
- 2026-06-19: **C7 ✅（canon#85・user GO で実装）= 0ベース review follow-up 本体 全完了**。
  `build-zmk.sh --reset`（実シールド据置 + `CONFIG_ZMK_SETTINGS_RESET_ON_START=y`、`--logging` と同じ
  ローカル flag 方式・build.yaml/CI/release 不変）で `*_RESET.uf2` を生成し flash-reset.sh の dead path を解消。
  gotcha: shield 差し替え方式は assimilator-bt の `spi1_default` pinctrl 未定義で失敗 → reset config だけ実シールドへ
  載せる方式で回避。shellcheck clean / 3 機種ビルド成功 / config 反映確認。実機 NVS 消去は user 検証。
  **残は Backlog の low/nit のみ（任意）**。
- 2026-06-19: **Backlog canon keymap#2 ✅（[canon#87](https://github.com/akira-toriyama/canon/pull/87)）**。
  v-key 移行で孤児化した複雑 MODS 残骸 3点（`ALL_MODS` define / drawer の陳腐化コメント /
  `special_combinations` `Hyper+`/`Meh+`）を削除。実調査で ledger 記載の 2点に加え special_combinations も
  dead（3〜4mod binding 不在）と判明し拡張。全て refactor T1（`73ea43c`）の掃除し残し。firmware/SVG 挙動不変。
  user が「v-key 動作確認済（キーボード）＝複雑 MODS 不要化」を確認済。
- 2026-06-19: **Backlog canon low/nit 4件 ✅（[canon#88](https://github.com/akira-toriyama/canon/pull/88)）**。
  gen#3（PR テンプレ vkey チェック）/ ci#3（awk 逆参照コメント）/ gen#4（eiji disp 1文字 assert）/
  gen#2（DEFAULT alias `KP_X1`→`VK_X1` 改名 + 再生成）を 1 nit=1 commit で回収。**3件は据置**:
  build#3（awk 抽出＝build クリティカルパス・blast radius 大）/ keymap#3（kana/eiji wrapper は drawer 表示名も
  担い素朴 de-dup は回帰）/ build#2（README user 主体・文案用意済で承認待ち）。gen#2 の chord 側 follow-up
  （live config `KP_X1`→`VK_X1`）は user の次回 chord 再同期で。
