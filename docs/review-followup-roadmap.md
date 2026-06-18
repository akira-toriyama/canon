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

## 進め方 / 検証

- **chord 先行**。順序: **C1 → C2 → C3 → C4**。canon（C5–C7）は後続セッション。
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
| C2 | dry-run / reload renderer 取りこぼし修正 | chord | High + Med×3 | ☐ TODO | – |
| C3 | ホットパス（handleVKey / Controller spine）テスト | chord | High + Med | ☐ TODO | – |
| C4 | 個別 Medium バグ（exclude_apps / typo section） | chord | Med×2 | ☐ TODO | – |
| C5 | dongle ビルドを必須チェックへ（**要 user 承認**） | canon | High | ☐ TODO | – |
| C6 | docs ドリフト一括修正（dongle / release / zmk-build / vkey） | canon | Med | ☐ TODO | – |
| C7 | flash-reset.sh dead path 解消（削除 or 実装） | canon | Med | ☐ TODO | – |
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

## C3. ホットパスのテスト空白を埋める　[High + Med]

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

## C4. 個別 Medium バグ（クラスタ外）　[Med×2]

- **matcher#1 — exclude_apps バイパス**: `Sources/ChordCore/Matcher.swift:138-159`
  (modifierTransitions) が global `excludeApps` を見ない（`find()` は尊重）。
  → globally 無効化したアプリで modifier-only binding（例: setVariable エッジ）が発火。
  **修正**: 関数頭に `if let id = bundleID, Matcher.matchesGlobs(id, patterns: excludeApps) { return [] }`。
  `ModifierTransitionsTests` に「除外 bundleID → エッジ無し」ケース追加。
- **parsing#1 — typo セクションを parser が黙認**: `[[bindigs]]` 等が
  `--validate --strict` を 0 通過（エディタ JSON schema の方が厳しい逆転）。
  `Sources/ChordCore/ConfigSchema/StructuralCheck.swift` は known セクション内部しか見ない。
  **修正**: `Config.parse` で root キーを `Set(ChordConfigSchema.sections.map(\.name))`
  （TOML.lineKey 除く）に照合し未知を warn（kind `.unknownKey`/`.unknownSection`）。
  test: `[[bindigs]]` で warning + `--strict` トリップ。

---

# canon（後続セッション）

## C5. dongle ビルドを必須チェックへ　[High・**要 user 承認**]

`build.yaml` の3ターゲット中 **dongle ビルドが main 保護 ruleset(id 16483994) の
required_status_checks に無い** → dongle を壊す PR がマージ可能 → マージ後 release.yml を壊す
（release.yml ヘッダが記録する既知の障害クラス）。
**対応**: ruleset 16483994 の required_status_checks に
`build / Build (xiao_ble/nrf52840/zmk, imprint_dongle)` を追加。**コード変更なし**。
**branch protection 変更は明示的な user 承認が必要**（refactor-roadmap の方針）→ 承認後に実施。

## C6. docs ドリフト一括修正　[Med・doc のみ]

現実から取り残された記述（機能影響ゼロだが CLAUDE.md は拘束力あり）:
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

## C7. flash-reset.sh dead path 解消　[Med]

`scripts/flash-reset.sh` → `flash-impl.sh:55` が `firmware/imprint_*_RESET.uf2` を参照するが
**それを生成する build target が存在しない**（必ず ERROR で死ぬ）。
**選択肢**: (a) flash-reset.sh と `_RESET` 配管を削除、(b) settings-reset ビルド経路
（ZMK `--snippet settings-reset`）を実装して文書化。
※ refactor-roadmap T2 が NVS-destructive 文言を意図的に残した経緯あり → **削除前に user 確認**。

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
- gen#1: gen-vkey-aliases.py がコメントも走査（将来 `// &vkey 0xNN` で誤爆）→ 行コメント除去。
- gen#2: DEFAULT alias `KP_X1` が chord 予約 `kp_*` 名前空間 → `VK_X1` 等へ改名し再生成。
- gen#3: PR テンプレに vkey 用チェック欠如（eiji にはある）→ sibling checkbox + verify-vkey-sync 追記。
- gen#4: eiji `disp:[X]` regex が幅検証なし → 1文字 assert で fail-loud。
- build#3: build-zmk.sh ↔ zmk-build.yml で patch-apply / west-build / awk が三重複
  （awk 抽出を `scripts/lib/parse-build-targets.sh` へ最初に切る、機会的に）。
- ci#3: 同 awk の相互参照コメントが片方向 → build-zmk.sh 側にも逆参照コメント。
- build#2: README が flash-watch.sh / dongle flashing 未記載（C7 解消後に最小追記）。
- keymap#2: `ALL_MODS` dead define（behavior_macros.h:23-24）削除 +
  keymap_drawer.config.yaml:140-142 の陳腐化コメント修正（arrow morph は Ctrl+Alt のみ）。
- keymap#3: kana/eiji 0-cell wrapper macro の冗長 indirection（任意 de-dup、draw 再実行必須）。

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
