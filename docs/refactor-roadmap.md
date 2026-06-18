# リファクタ ロードマップ (canon + chord)

ZMK 側 ([`canon`](https://github.com/akira-toriyama/canon)) と macOS host
bridge ([`chord`](https://github.com/akira-toriyama/chord)) を横断する
**net-new リファクタ**の引き継ぎメモ。複数セッションにまたがるため、
優先度・依存順・判断ポイント・**あえてやらない一覧（未達成を暗黙に落とさない）**
をここに集約する。

> 進め方の前提（ユーザー指示）: **破壊的変更 OK** / **品質優先** /
> **複数セッション可（計画と実行を分けてよい）** / **引き継ぎメモ必須** /
> **未達成を暗黙にしない**。本書はその引き継ぎメモを兼ねる。

## ✅ 完了サマリ（2026-06-18）

**全 7 トラック完了・全 PR マージ済み**。両 repo とも `main`。各トラック
= 1 issue + 1 PR（T7 のみ 2 PR）で landing、CI green を確認してから merge。

| #  | PR | issue | merge commit |
|----|----|-------|--------------|
| T1 | canon #66 | #63 | `73ea43c` |
| T2 | canon #67 | #64 | `59a3d96` |
| T4-A | canon #68 | #65 | `79000c7`（+ main ruleset 必須チェック名を `lint`→`lint / lint` に更新）|
| T3 | chord #101 | #99 | `4dbd74e` |
| T4-B | chord #102 | #100 | `b7e6366` |
| T5 | chord #103 | #52 | `cb132a7` |
| T6 | chord #105 | #104 | `787489d` |
| T7a | chord #107 | #106 | `af77b30` |
| T7b | chord #109 | #108 | `1db29db` |

判断ポイント①②③はすべて解決（下「判断ポイント」参照）。破壊的変更は無し
（全 `breaking:false`・wire/挙動中立）。chord ローカル gate は `swift build`、
`swift test` は Xcode CI（`build` check）がゲート。

## 生成元・信頼度

- 2026-06-18 の ultracode マルチエージェント走査（42 agents・12 レンズ＝
  chord 7 / canon 4 / cross 1）。各 finding を**敵対的検証**（「却下を前提に潰す」
  検証エージェント）に通し、29 findings → **21 survive**。
- canon 側（T1/T2）と cross（T4）は**本セッションで実コードに再照合済み**（下表 ✔）。
  chord 側（T3/T5/T6/T7）は走査エージェントの調査ベース。実行セッション着手時に
  各 location を再確認すること（行番号はこの時点のもの。ドリフトしうる）。

## 凡例

- 状態: ⬜ 未着手 / 🔄 進行中 / ✅ 完了 / ⏸️ 判断待ち
- effort: S（〜1h）/ M（半日）/ L（1 日＋）
- risk: low / medium（high は今回なし）

## トラック一覧

| #  | Track                                              | repo  | Pri | eff/risk | 検証元 | 状態 |
|----|----------------------------------------------------|-------|-----|----------|--------|------|
| T1 | dead modifier-chord 機構の削除（vkey 移行の遺物）    | canon | P0  | S/low    | ✔      | ✅   |
| T2 | flash スクリプト + build.yaml parser の dedup       | canon | P1  | S/low    | ✔      | ✅   |
| T3 | chord dev plist 単一ソース化 + pkill path 修正      | chord | P1  | M/med    | ✔      | ✅   |
| T4 | commit-lint を shared reusable へ収束 + security 整合 | cross | P1  | S/low    | ✔      | ✅   |
| T5 | ChordCore parsing/schema の単一ソース化（6 件束）    | chord | P2  | S–M/low  | ✔      | ✅   |
| T6 | ChordCore テスト支援 helper + XCTUnwrap 一掃        | chord | P2  | M/low    | ✔      | ✅   |
| T7 | VariableStore を ChordCore へ抽出（+ modifier-edge）| chord | P2  | L/med    | ✔      | ✅   |

### 実行ログ（セッション 2026-06-18）

完了した 4 トラックは各々ローカルで検証済（未 push / 未 PR）。各ブランチは
それぞれの repo の main から独立。

| T  | repo  | branch | commit(s) | 検証 |
|----|-------|--------|-----------|------|
| T1 | canon | `refactor/t1-dead-modifier-chord` | `daf40b7` | `build-zmk.sh imprint_left` 成功（zmk.elf・uf2、FLASH 24.75%） |
| T2 | canon | `refactor/t2-flash-and-build-dedup` | `4b332d8` | shellcheck 4 本 PASS / parser 旧実装と diff 一致 |
| T4-A | canon | `refactor/t4a-commit-lint-shared-reusable` | `6d16524` | YAML OK / 直近 20 件が共有 grammar 通過 |
| T4-B | chord | `refactor/t4b-drop-security-type` | `f5a0ffe` | hook が `security` を REJECT・通常は PASS |
| T3 | chord | `refactor/t3-plist-and-pkill` | `8c505e0`(refactor) `e568593`(fix) | 派生 plist が旧 twin と全キー一致 / shellcheck PASS / version-sync OK |
| T5 | chord | `refactor/t5-parsing-schema-single-source` | `cb132a7`(squash #103) | `swift build` + `SingleSourceT5Tests`（CI `build` green）|
| T6 | chord | `refactor/t6-test-helpers` | `787489d`(squash #105) | 14 ファイル移行・残存 `as!` 0（CI `build` green）|
| T7a | chord | `refactor/t7a-variable-store` | `af77b30`(squash #107) | Controller 846→711 行・`VariableStoreTests`（CI `build` green）|
| T7b | chord | `refactor/t7b-modifier-edge` | `1db29db`(squash #109) | `ModifierTransitionsTests`（CI `build` green。初回はテストの event マスク誤りで fail→side-specific へ修正し pass）|

**全完了**。全ブランチ merge 後に delete 済み（chord は squash・(#N) 付与、canon は rebase）。
chord ハード依存 T6→T7 は順守、T5 は T7 より先に landing。

**判断（すべて解決）**: ①`security` type は chord から削除（下げ揃え）。
②canon commit-lint は英語 shared reusable へ収束（CI 失敗文言は英語）。**この収束で
main の ruleset 必須チェック名が `lint`→`lint / lint` に変わるため ruleset も更新**
（ユーザー承認済・branch-protection 変更）。③ T5=1 束 PR、T7=2 PR（store→edge）に分割。

破壊的変更（公開 API/wire/挙動）は**いずれも無し**（全 `breaking:false`）。
"破壊的変更 OK" だが、結果的にこの 21 件は内部構造の改善に収まった。

## 進め方（sequencing）

安全・決定的なものを先、依存を尊重:

1. **T1（P0・canon）** 最優先。confidence 0.95、挙動中立、単一 PR。marquee
   機能（vkey）の doc-drift を解消。依存なし。
2. **T2（P1・canon）** T1 と別ファイルなので並行可。shellcheck ゲート。
3. **T3（P1・chord）** scripts/packaging のみ。Swift 非依存で canon トラックと並行可。
4. **T4（P1・cross）** CI/hook/doc のみ。**判断 1・2 を解決してから** merge。
5. **T5（P2・chord）** 構造依存は無いが、**T7 より前**に landing 推奨
   （同じ Models.swift/Controller を触るため、小さい機械的 PR を先に通すとレビューが楽）。
6. **T6（P2・chord）** **T7 の前提（ハード依存）**。新テストを正規の round-trip
   helper の上に乗せるため。XCTUnwrap 一掃のサブ項目は完全独立でいつでも可。
7. **T7（P2・chord）** L-effort/medium-risk。**最後**。T6（テスト基盤）に依存、
   T5 が Controller/Models の churn を先に片付けている前提が望ましい。
   2 PR に分割（先 VariableStore → 後 modifier-edge）。

横断: canon(T1,T2) と chord(T3,T5,T6,T7) はセッションを跨いで並行可。
chord 内のハード依存は **T6 → T7** のみ。T5 は T7 より soft-before。

---

## 各トラック詳細

### T1 [P0] dead modifier-chord 機構の削除（canon）✔再確認済

`ffa4e49`（サム 4 層を `&vkey` 化・修飾子 chord 全廃）で孤児化した機構が
**定義されているが一切呼ばれていない**。`imprint.keymap` から到達不能を grep 確認済。
削除しても挙動中立。残存コメントは「現ファームが実装していない仕組み」を説明していて
**vkey の理解を誤らせる**ので併せて除去。

- **item A** [config/macros.dtsi](../config/macros.dtsi) — `CHORD_KP_REL(ll_kp)`
  / `CHORD_KP_REL(lm_kp)` / `CHORD_KP(rm_kp)` / `CHORD_KP(rr_kp)` の 4 実体（41–44 行・
  直前コメント込み）と、不正確な「右 4 修飾子のうち 3 つ / OS 側でレイヤー識別」説明
  ブロック（27–34 行付近）を削除。**残す**: live な TU セクション（ヘッダコメント・
  `TU_MOD(t_ll_ctrl)` / `TU_MOD(t_lm_alt)`）。
- **item B** [config/behavior_macros.h](../config/behavior_macros.h) — `CHORD_KP`/
  `CHORD_KP_REL` マクロ定義（162–178 行）と `X_1..X_4` define（25–28 行）＋その stale
  コメント（23 行・「`&kp X_1` で使う」は誤り）を削除。**残す**: `TU_MOD`（155–160）と
  `TU_LL/TU_LM/TU_RM/TU_RR`（38–41。`imprint.keymap:45` で live）。
- **注意**: C の `X_1..X_4` define は `vkey-aliases.toml` の `X1..X4` alias 名トークンとは
  **無関係**（別物）。混同して後者を消さないこと。
- **verify**: `./scripts/build-zmk.sh` で preprocessor/devicetree が解決することを確認
  → push で [build.yml](../.github/workflows/build.yml) がゲート。`verify-vkey-sync`
  はこのマクロではなく `&vkey` id を読むので影響なし。

### T2 [P1] flash スクリプト + build.yaml parser の dedup（canon）✔再確認済

- **item A** — [scripts/flash-watch.sh](../scripts/flash-watch.sh) と
  [scripts/flash-reset.sh](../scripts/flash-reset.sh) は ~95% 同一（差分は `_RESET`
  suffix とオペレータ向け文言のみ）。`scripts/flash-impl.sh` を `arg1=SUFFIX`（`''`/`_RESET`）
  ＋ per-device / ALL-DONE のラベル引数で parametrize し、2 本を ~5 行の thin wrapper に。
  **文言はジェネリック化しない**（NVS 破壊操作中の意図伝達のため `device will reboot`
  vs `NVS wiped` を保持）。`set -u` / `cd ..` / `# shellcheck disable=SC2001` を温存。
- **item B** — [scripts/build-zmk.sh](../scripts/build-zmk.sh) の build.yaml awk parser が
  2 箇所（57–66 / 77–90）に複製。`_build_pairs()`（awk を 1 回実行し `board\tshield` 行を
  出力）に集約。shield 指定パスは `_build_pairs` を shell filter（`IFS=$'\t' read` + 完全一致 +
  first-match `break`）で。新依存なし（純 shell+awk）。
- **verify**: [shellcheck.yml](../.github/workflows/shellcheck.yml) ゲート。`build-zmk.sh`
  を no-arg と shield 引数の両方で実行し board 解決を確認。

### T3 [P1] chord dev plist 単一ソース化 + pkill path 修正（chord）

- **item A** — `Info.plist.dev` は `Info.plist` の twin で、CI は version 行しか守らない
  （他 4 派生フィールドや v-key NSInputMonitoring 文言などの新規キーは無防備）。
  `package.sh --dev` で `Info.plist` をコピーし `plutil -replace`（CFBundleName/
  Identifier/Executable/ShortVersionString）＋ 2 つの `*UsageDescription` 文字列を派生生成し、
  `Info.plist.dev` を**削除**。`scripts/check-version-sync.sh` は
  `ChordVersion.current == Info.plist CFBundleShortVersionString` の 1 アサーションに縮小。
  eiji/vkey の単一ソース規律と同型。
- **item B**（独立バグ）— `scripts/install-launchagent.sh:76` / `uninstall-launchagent.sh:32-35`
  の straggler-kill が `~/dev/chord` を**ハードコード**。それ以外の checkout（例: この
  ネットワークボリューム）では teardown が**黙って no-op**。`cd "$(dirname $0)/.."` 後に
  `REPO=$(pwd)` を取り、`pkill -f "$REPO/\.build/(debug|release)/chord"` に。`/Applications`
  バンドルの pkill 行と brew 共存コメントは温存。`stop.sh` には広げない。
- **risk medium** は item A（plutil 変換の取りこぼし）由来。
- **verify**: `package.sh --dev` の生成 plist を旧 `Info.plist.dev` と diff（5 派生フィールド
  一致）/ `check-version-sync.sh`（build.yml の local step・必須ゲート）/ shellcheck。

### T4 [P1] commit-lint 収束 + security type 整合（cross）✔再確認済 ⏸️判断待ち

- **item A** — canon の [commit-lint.yml](../.github/workflows/commit-lint.yml) は ~40 行の
  inline shell バリデータ。chord は既に `akira-toriyama/.github/.github/workflows/commit-lint.yml@main`
  への thin caller。**canon が唯一の inline holdout**（ロジックは shared reusable と byte 同一）。
  canon を thin caller 化し、shared workflow ヘッダの caller リストに canon を追記。
  glossary.yml は既に reusable 委譲済なので低依存/no-paid-CI ポリシーの障害なし
  （GitHub-hosted 無料・Node/Claude なし）。**判断 2 参照**。
- **item B** — chord の `scripts/hooks/commit-msg:22` と `docs/commit-convention.md:29` は
  `security` type（`:lock:`）を許すが、shared reusable CI（許可型 = `feat|fix|perf|refactor|
  docs|test|build|ci|chore|style|revert`、security なし）は**拒否**し、chord の cliff.toml にも
  `^security` parser が無い（changelog/版算出から黙って漏れる）。つまり `security` コミットは
  **local hook を通って CI で落ちる**自己矛盾。**chord のみ**で hook と doc から削除し、
  authoritative な shared grammar に揃える（security 相当は fix/chore に乗せる）。**判断 1 参照**。
- **verify**: PR を開き commit-lint check（= shared reusable）がゲート。bot-skip（draw-keymap
  の `:bento:` bot）が引き続き除外されることを確認。chord 側は `:lock: security(...)` を書いて
  hook が**拒否する**ことを確認。

### T5 [P2] ChordCore parsing/schema の単一ソース化（chord・6 件束）

いずれも platform-pure（AppKit/Dispatch 非依存）、Xcode テストゲート、挙動中立。
drift 正しさを「レビュー不変条件」から「構造的保証」へ。overlapping ファイルなので
**まとめて or 2–3 small PR**。P0/P1 の後に landing し critical path から外す。

- **a** 2 つの並行 modifier-token リストを 1 table に（`InputParser.swift:142-156` と `205-255`）。
  `reservedModifierTokens = Set(table.keys)` を導出。`Schema.swift` の inverse mapping は**対象外**
  （別物・PR に注記）。
- **b** Action kind 文字列を `Action` enum に単一ソース化（`Models.swift` に `kindString`、
  `Schema.swift:602-651` / `Controller.swift:195-203` の手書きリテラルを置換）。将来の case 追加が
  コンパイルエラーになる。`Main.printBindingSection` と `ReloadDiffPrinter` は触らない。
- **c** modifier の (any,left,right) side-category table を `Modifiers` に（`Models.swift:64-114` /
  `Schema.swift:542-556`）。`isStillHeld` の permissive セマンティクスは保持（table 化するが
  hold-while の意味は変えない）。
- **d** `v-key`/`vkey` wildcard 名チェックを集約（`InputParser.swift:69` に
  `vkeyWildcardNames`、`Config.swift:199` / `Config+Remap.swift:102` / `Config+Sequence.swift:201`
  の inline guard を置換）。
- **e** `__line__` row source-line accessor を抽出（`Dictionary where Value==TOML.Value` に
  `sourceLine`）。7 reader site を置換、dead な Int64-era `.map { Int($0) }` を除去。
- **f** `WireAction` の 5 つの full-field constructor を defaulted-nil init に（`Schema.swift`）。
  JSON wire shape は byte 同一。**任意の cleanup**。
- **verify**: 各項目に対応する小テスト追加（table key の round-trip / `kindString` 一致 等）。
  `swift test`（Xcode CI）。

### T6 [P2] ChordCore テスト支援 helper + XCTUnwrap 一掃（chord）

test-only・本番リスク無し。**T7 の前提**。

- **a** 共有の `parseToBindingsJSON(_:)`（parse→makeDocument→encodeJSON→jsonObject、XCTUnwrap 経由）
  と `firstBinding(_:)` を `Tests/ChordCoreTests` の XCTestCase extension に（Package.swift 変更不要）。
  ~14 の inline full-chain コピーと ~18 の `as!` 取り出しを移行。**移行しない**: `DiffTests.doc`
  / `QuerySchemaTests.object` / `ConfigSchemaShapeTests`（別スキーマ・重複ではない）。
- **b**（独立）JSON-shape テストの `as!` force-cast を `try XCTUnwrap(... as? ...)` に一掃
  （SchemaTests / StateTests / MultiVarConditionTests / ToggleHoldVarTests / ActionKeysArrayTests /
  AutorepeatTests）。shape 不一致が process-abort でなく file:line 付き局所失敗になる。
- **verify**: `swift test`（Xcode CI）。出力は同一、setup のみ集約。

### T7 [P2] VariableStore を ChordCore へ抽出（chord・L）

リポジトリ最大の god-object（`Controller.swift` ~850 行の最大要因）かつ**最も難しい並行
ロジックが直接カバレッジ 0**。唯一の integration test は store を手で wipe している
（`TestEventSourceTests.swift:105` が real な `timerFired`/`extendTimer`/hold-while に到達不能）。

- **a** Foundation-only `final class VariableStore`（自前 NSLock・value-typed `VariableEntry`）を
  ChordCore に抽出。surface: `snapshot()` / `set(name,value,holdWhile,timeoutMs)` /
  `toggle(name)->(old,new)`（**単一ロック窓**で。`Controller.swift:314-331` の atomicity 不変条件を
  保持・snapshot+set に分割しない）/ `extendTimer` / `clearStale(currentMods:)->[clearedNames]` /
  `reset()`。`DispatchSourceTimer`+`stateTimerQueue` は **Core の外**に最小 `Scheduler` protocol
  （`schedule(afterMs:_ fire:@Sendable)->Cancelable`, `cancel/cancelAll`）で。Controller は
  DispatchSource 実装を注入、テストは manual/virtual clock を注入。file-private global 4 つが
  1 オブジェクトに集約。既存 `EventSource` protocol 抽象と同型。**スコープ**: store ロジックの
  単体テスト化のみ（Controller の event-routing wiring は integration のまま）。
- **b** modifier-only entry/exit edge ロジックを Matcher（ChordCore）へ。pure な
  `modifierTransitions(prev:curr:state:bundleID:) -> [(Binding, ModifierEdge)]` を追加し、
  `Controller.fireModifierOnlyBindings`（424-460）は lock+swap・early-out・Matcher 呼び・
  `fireBindingAction` だけに縮小（`appsAllow`/`conditionHolds` の再実装を排除、`b.action=onUp`
  mutation を除去）。
- **verify**: 新 ChordCoreTests（0-clears-entry / atomic toggle race / reset-on-use extends /
  hold-while clearStale / timeout-fires→cleared / reset-on-reload wipes、enter/exit edge）。
  既存 ChordIntegrationTests は green 維持（real store を駆動できるようになる）。`swift test`（Xcode CI）。

---

## 判断ポイント（すべて解決 ✅）

1. **`security` commit type の扱い（T4-B）** → **下げ揃え**で決定（chord の hook+doc から削除）。
   chord #102 で landing。
2. **canon commit-lint の CI 文言（T4-A）** → **収束**で決定（shared reusable・CI 失敗文言は英語）。
   canon #68 で landing。**副作用**: 収束で main ruleset の必須チェック名が `lint`→`lint / lint`
   に変わるため ruleset 更新が必要だった（ユーザー承認のうえ更新）。当初の計画には無かった手順で、
   reusable 収束＝必須チェック名変更を伴う点は今後の同種収束時の注意。
3. **T5/T7 の PR 粒度** → T5=1 束 PR（#103）、T7=2 PR（#107 store → #109 edge）で実行。

---

## 未達成 / あえてやらない（未達成を暗黙にしない）

走査で検討したが**意図的に計画に載せなかった**もの。理由付きで残す。

**chord（clean 判定・churn 回避）**
- QueryServer/Control の POSIX socket（sockaddr_un+setsockopt）dedup — bind/listen 側と
  connect/send 側で別 type に分かれているのは正しい層分け。共有 helper は Control/Controller
  境界を跨いで益が薄い。
- FrontmostTracker/InputSourceTracker の `CachedValue<T>` 共通化 — 差分部
  （NSWorkspace+@MainActor vs DistributedNotificationCenter+Carbon TIS）が支配的。共有 ~10 行。
  generic base は低依存スタイルへの churn。
- `Controller.handle()` の hot-path switch 分解 — daemon の中核決定木で inline 根拠コメントが優秀。
  分割は可読性を**下げる**。
- `Schema.swift modifierTokens(_:)` の inverse mapping 統一 — parse 側の alias 多綴り ↔ emit 側
  canonical 1 トークンで**逆写像が一致しない**。強引な fold。T5-a の PR に注記。
- QuerySchema の共有 header struct / Log.swift watch-emit 共通化 — wire nesting を変える / 差分が
  支配的で低価値。
- `makeInputEvent` の mouse-arm 6 重複 — 実在するが低価値。将来 EventTap.swift を触る折に
  **opportunistic** に畳む（単独 churn PR にしない）。
- **（T5 実装中に発見・意図的に対象外）** `ChordAdapterMacOS/SideMaskTable.swift`
  （CGEvent flag→`Modifiers` の HID 側マッピング）は T5-c の `Modifiers.sideCategories`
  とは別関心（platform-pure でない adapter 層）。T5 では触らず。将来 EventTap を触る折に検討。
- **（T5 item e で対象外）** `Config.swift` の vkey-id 読み取り `value.asInt.map { Int($0) }`
  は dead な Int64-era cast だが**行読み取りでない**ため item e（`__line__` reader）の scope 外。
  残置（次に Config.swift の alias 解析を触る折に opportunistic）。

**canon**
- `vkey-roadmap.md` の履歴アーカイブ（同一ファイル内圧縮）— 低価値の内部 doc 整理で anchor/link
  破壊リスク。**次にこの doc を触る折に opportunistic**（confidence 0.55）。
- `vkey-roadmap.md` の 4 セクション dedup — **「shipped 項目を done と明記する数行の staleness 修正」
  に格下げ**。4 つの異なる genre を flatten すると**ユーザーが追跡を求める deferred 項目を落とす
  リスク**があるためフラット化はしない。
- taplo/TOML lint 採用 — **却下**。canon に手編集 TOML は無い（cliff.toml + 生成物
  vkey-aliases.toml のみ）。linter は stdlib-only/低依存 charter に反する。
- release.yml / zmk-build.yml の shared reusable 収束 — **却下**。ZMK ドメイン固有（uf2/
  rolling-draft）で、Swift-app 用の shared release.yml には収束不能。shared ヘッダ自身が
  domain-specific flow を non-caller として明記している。
- `patches/zmk/*` の削除 — **upstream 状態による保留（リファクタではない）**。zmk#3384/#3385/#3390
  は全て **OPEN**（gh 確認済）。3 patch とも merge まで維持（「merge され次第畳む」は正しく文書化済）。
- cliff.toml の cross-repo 単一ソース化 — 意図的に near-identical だが各 repo の release flow
  （canon 手動 tag vs chord rolling-draft）に密結合。30 行 TOML の横断 factoring は割に合わない。

**プロダクト scope（リファクタ対象外・既存 doc で追跡済）**
- BLE-HOG / dongle RGB の descope — [vkey-roadmap.md](vkey-roadmap.md) の未達成リスト /
  [dongle-roadmap.md](dongle-roadmap.md) Phase 6 で追跡済。verbatim 保持。リファクタ action なし。
- dotfiles chezmoi `private_config.toml`（chord `[v-key-aliases]` 貼付先）— **明示的にスコープ外**
  （ユーザー管理）。点検も変更もしない。

**既に十分（再提案しない）**
- chord section-E 抽出 / Main.swift CLI dispatch 分割（#93/#94/#95）— 完了済・良好。
- chord descriptor model（#85）/ ChordConfigSchema 単一ソース — 既に exemplary。

---

## このスキャンで clean だった領域（再走査不要の記録）

12 レンズ走査で**所見なし＝既に健全**と判定した範囲（重複走査の無駄を避けるための記録）:
chord の hexagonal 層分離（Core 純度）、descriptor-driven validation、CLI subcommand table、
globMatch（#55 で線形化済）、TOML（swift-toml-edit 由来・in-tree parser 撤去済）、
chord→norm CI 収束（build/release/update-tap = 3/3 済）。canon の単一ソース生成器
（eiji / vkey）と verify-*-sync ゲート、ZMK root-file 配置、west/patch 機構。

> **本ロードマップは全 7 トラック完了（全 PR マージ済み）。** 以降は記録として保持する
> — 「あえてやらない」一覧は将来の opportunistic 対応の起点として残す。新規リファクタは
> 別途このフォーマットで起票する。
