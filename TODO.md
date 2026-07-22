# Kotlin Compiler Remaining Tasks

最終更新: 2026-07-17（DEADCODE-CORE-030 完了: `TypeInferenceContext.swift` の未使用 `with(enclosingClassSymbol:)` を削除。同日: DEADCODE-CORE-034 完了: `SyntheticStubSurfaceSpec.swift` の未参照 static `ubyte` 型参照定数を削除。同日: PR #4578 の CI 失敗調査で `launch{}` cancel-before-start レース（`kk_kxmini_launch`, `Sources/Runtime/RuntimeCoroutine.swift`）を確認、BUG-041 を追補。master 側の BUG-039/040（RuntimeTests CI の cross-suite GC race / exec引数長制限）とは無関係の別問題。それ以前: master CI 失敗調査で BUG-039 の暫定緩和(PR #4846, `SWIFT_TEST_PARALLEL=0`)が Linux exec() 引数長制限に抵触し `Full Swift Tests (RuntimeTests)` を落とし続けていたことを確認、BUG-040 を追補し CI 側を修正。それ以前 2026-07-16: master CI 失敗調査で BUG-023/024/028 が実際に master 上で発火していることを確認し、BUG-039 を追補。それ以前: 2026-07-13 dead-code 再監査と、オープンPR一括レビューで判明した Swift Testing 移行の変換不備を追補。BUG-020〜035 は canImport ガード不備、tearDown 消失系、`.serialized` 欠落系などを扱う）

---

## 全体リファクタリング計画（RF0–RF9）
> 調査日: 2026-06-10。実測: CompilerCore ~229k 行（うち Sema/DataFlow ~104k、合成スタブ約100ファイル/~9万行）、
> Runtime ~63k 行、Tests ~214k 行、`interner.resolve == "名前"` 特例 104 箇所（TypeCheck）、`"kk_` リテラル 6,738 箇所（CompilerCore）。
> 方針: (1) 削除予定コードは磨かない（リネーム・分割をしない） (2) 各タスクは独立 PR サイズ
> (3) 完了ゲートは既存の `swift_test.sh` / golden / `diff_kotlinc.sh` / jscpd を流用
> (4) M1–M17・cleanup-stub 系とは重複させず、本計画はその「前提基盤」と「それ以外の負債」を扱う。

### Phase RF0+RF8: 計測・ガードレールと継続ガバナンス（残り 3 件）
- [ ] RF-GUARD-002: `.jscpd.json` の `path` に `Tests/` を追加し重複率を再計測する（まず report-only ジョブで観測、閾値は実測後に設定。現状 Tests/ は完全に未監視）
- [ ] RF-GOV-001: jscpd 閾値を重複削減の進行に合わせて段階的に引き下げる（現状 5.6%。ignore 3 ファイルの解消とセット）
- [ ] RF-GOV-003: 各 RF フェーズの最終タスクとして `docs/ARCHITECTURE.md` の数値・ファイルリスト更新を必須化する

### Phase RF2+RF3+RF4+RF5: Stdlib パイプライン・合成スタブ削減・名前文字列特殊処理排除・Lowering 再編（残り 7 件）
> 背景: `HeaderHelpers+Synthetic*` 約100ファイル/~9万行。ボイラープレート率 60–70%。登録呼び出しは `registerSyntheticDelegateStubs` に 85+ 連鎖。
> 背景: TypeCheck に `interner.resolve(...) == "名前"` が 104 箇所、`CallLowerer+LegacyMemberLikeCalls.swift` は 4,055 行・`kk_` リテラル 601 個。
- [~] RF-STDLIB-002: `LoadSourcesPhase` に bundled Stdlib ソース読み込みを実装する（`Bundle.module` 列挙 → `sourceManager` 登録は基本配線済み。残: `--no-stdlib` での opt-out、source origin、ユーザー入力との診断パス区別）。残作業は `KSP-INF-001` / `KSP-INF-008` と連携して完了させる。
- [~] RF-STUB-003: (c) 残留スタブ向けの宣言的登録 API を導入する（RuntimeABI の `StdlibSurfaceSpec` パターンを Sema 登録へ拡張し、~340 個の `registerXxxMember` 手書き関数をデータテーブル化）。2026-07-07: `SyntheticConstructorStubSpec` と fallback 型参照を追加し、`SyntheticStubSurfaceSpec+NativeRefRuntime.swift` へ `WeakReference` / `GC` / `GCInfo` / `Debugging` surface を移行。
- [~] RF-SEMA-002: `markStdlibSpecialCallExpr` 系特例（repeat / measureTime* / Array コンストラクタ等）をシンボル登録時メタデータ（flags / annotation）駆動の共通機構へ置換し、2–3 例を移して実証する。2026-07-06: `repeat` と `kotlin.system.measureTimeMillis/measureTimeMicros/measureNanoTime` は `StdlibSpecialCallKind` metadata 駆動の入口へ移行済み。残: `kotlin.time.measureTime/measureTimedValue`、Array/primitive array constructor、atomic array factory、`typeOf` 等
- [ ] RF-SEMA-003: `CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift`（2,157 行・17 特例）を、宣言充実に合わせて特例単位で段階削除する
- [ ] RF-KIR-003: 同 第3弾（Collection 系）を移行し、ファイルを解体して "Legacy" の名称を消滅させる
- [ ] RF-LOWER-004: `InlineLoweringPass`（1,280 行）と `LambdaClosureConversionPass` の共有ヘルパーを抽出する（`InlineLoweringPass.swift:428` の既知 TODO）
- [ ] RF-LOWER-006: `DataEnumSealedSynthesisPass+DataClassMethods`（1,268 行・TODO 33 件）を整理し、`.jscpd.json` の ignore 固定 3 ファイルを解消する

### Phase RF6: Runtime 縮小・ABI 整合（M タスク進行と連動）（残り 2 件）
- [ ] RF-RT-001: Range HOF 3 ファイル（Int / Long / UInt-ULong、~1.5k 行）の型別重複を Swift generics で統合する
- [ ] RF-RT-004: `RuntimeCollectionHOF`（3,183 行）と `RuntimeSequence`（3,867 行）の fold/reduce/filter/map 系共通化可能箇所を調査し統合する

### Phase RF7: テスト資産再編（残り 4 件）
- [ ] RF-TEST-001: Codegen 統合テスト（`CodegenBackendIntegrationTests+*` 214 ファイル・ボイラープレート ~13k 行）向けの fixture 駆動ハーネスを設計し、1 領域を移行する実証 PR を出す（.kt + expected stdout ペア、`Scripts/diff_cases` と同形式）
- [ ] RF-TEST-002: fixture 化を領域単位で展開し、「新規 Codegen 実行テストは fixture 必須」のガイドラインを `docs/ARCHITECTURE.md` に追記する
- [ ] RF-TEST-004: `SemanticsAndUtilitiesRegressionTests.swift`（3,520 行）を責務別に分割する
- [ ] RF-TEST-005: GoldenCases/Sema 244 ケースのうち同型ケース（minof_* / maxof_* 等）をパラメタライズ統合する
## 技術負債バックログ（コード監査 2026-06-12）
> 2026-06-12 のコード監査で検出した、RF0–RF8 と重複しない単発の負債タスク。記載の行番号・件数はすべて実コードで検証済み。
> 方針: (1) 各タスクは独立 PR サイズでフェーズ依存なく着手可（依存があるものは本文に明記） (2) 合成スタブ（`HeaderHelpers+Synthetic*`）のリネーム・分割は stub inventory の (a)(b)(c) 分類が先（「削除予定コードは磨かない」原則）のため本セクションでは扱わない (3) 完了ゲートは refactor PR gate と同じ（全テスト + golden + `diff_kotlinc.sh` green）。

### Runtime 正確性・コルーチン（残り 2 件）
> kotlinc では catch 可能な例外になるべき箇所がプロセス即死する。SPEC-NUM-0002（ゼロ除算 SIGFPE）と同型の問題系。
- [x] DEBT-RT-007: `kk_list_of_not_null` が `RuntimeListBox` を `listRuntimeTypeID` なしで登録するため、生成リストの要素列は正しくても `size` が 0 になる。最小再現: `val xs = listOfNotNull(1, null, 2); println(xs.size)`（`Scripts/diff_cases/list_of_not_null.kt` / KSP-311 CI）。`registerRuntimeObject(RuntimeListBox(elements: elements), typeID: listRuntimeTypeID)` に修正済み（PR #4594、マージ後に `[x]` 化）
- [ ] DEBT-CORO-005: `launch { ... }` 直後の `cancel()` で、開始前キャンセルされるべき child body が先に実行される scheduling race を調査・修正する。最小再現: `runBlocking { val job = launch { try { delay(Long.MAX_VALUE) } finally { println("finally") } }; job.cancel(); job.join() }` は JVM kotlinc では `finally` を出力しないが、kswiftc では出力する場合がある。PR #4632 の `kotlinc Diff Regression Shard (1/11)` で発見。該当 diff case は child を明示的に開始してから cancel する決定論的な形へ修正済み

### KIR / Lowering（残り 4 件）
- [ ] DEBT-KIR-004: 自己参照ではない `x or y` において、`y` が直前の関数呼び出し結果（例: `String.indexOf`）の場合に右オペランドが無視され 0 として計算されるバグを調査・修正する。再現: `val value = alphabet.indexOf(c); val r = 0 or value` は `r == 0`（誤り、正しくは `value`）になるが `value or 0` は正しく計算される。KSP-482 (#4625) の `Sources/CompilerCore/Stdlib/kotlin/io/encoding/Base64.kt:107` (`decodeRaw`) でオペランド順序を入れ替えるワークアラウンドを適用済み（コメント参照）。`and`/`xor` 等の他ビット演算子でも同型の問題がないか要確認
- [ ] DEBT-KIR-005: `for (x in byteArray)` が ByteArray の直接イテレーションでループ本体を一度も実行しないバグを調査・修正する。再現: `for (b in "HI".encodeToByteArray()) { println(b) }` は何も出力しないが、`while` + インデックスアクセス（`bytes[i]`）に書き換えると正しく動作する。KSP-482 (#4625) のレビュー対応中に `OutputStream.encodingWith` の手動検証スクリプトで発覚（Base64 実装自体は影響を受けない）。IntArray/List 等の他コレクション型で同型の問題がないか要確認。**原因判明・修正 PR: #4843**（配列型は実 `iterator()` を持たず `LoopIterationBinding` が付かないため、KIR 下降が Range 用汎用フォールバック `kk_range_iterator`/`hasNext`/`next` に落ち、`CollectionLiteralLoweringPass` の書き換えブリッジに配列用分岐が欠落していたため未変換のまま呼ばれていた。List/Set/Map/String は専用分岐がありこの問題の対象外。IntArray/FloatArray/DoubleArray/BooleanArray/CharArray/`Array<T>` も同型で影響を受ける。修正は `ControlFlowLowerer.lowerForExpr` で配列型を検出し `kk_array_size`/`kk_array_get_inbounds` によるインデックスベースループへ直接下降）。マージ後に `[x]` 化
- [ ] DEBT-KIR-006: `Iterable<T>.joinToString(separator) { transform }` の transform ラムダが無視され、各要素の生の `toString()` がそのまま結合されるバグを調査・修正する。再現: `"a\r\nbb\r\nccc".split("\r\n").joinToString(",") { it.length.toString() }` は `"a,bb,ccc"`（誤り、正しくは `"1,2,3"`）になる。`split` 自体・`for` ループでの個別アクセスは正しく動作する。KSP-482 (#4625) のレビュー対応中に Base64.Pem の行長検証 diff case で発覚、該当箇所は `for` ループへ書き換えて回避済み。`map`/`filter` 等の他 HOF で同型の transform 無視パターンがないか要確認
- [ ] DEBT-KIR-008: クラスインスタンスの委譲プロパティを per-instance storage にする。症状: `class Foo(val label: String) { val x by lazy { label } }; val a = Foo("a"); val b = Foo("b"); println(a.x); println(b.x)` は kotlinc では `a` / `b` だが kswiftc では `0` / `0` になる。`delegateStorageSymbol` が `nominalLayout` の field offset に登録されず、`MemberLowerer+DelegatedAndAccessorLowering.swift` の accessor は `.loadGlobal`、`KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift` の initializer は global 相当の `.symbolRef` copy を使うため、layout 登録・getter・setter・initializer をまとめて instance field 化する必要がある。PR #4632 の conflict repair 中にレビュー由来の再現を現行 `master` で再確認（#4692 は stdlib delegate factory の引数 lowering を修正したが storage ownership は未修正）

### Sema 型チェック（残り 1 件）
- [ ] DEBT-SEMA-001: 同一クラス内の後方宣言 member property を先行 member function から参照すると不正な型エラーになる。最小再現: `class Forward { fun get(): Int = value; var value = 10 }` は Kotlin では正当だが kswiftc は `KSWIFTK-TYPE-0001: Type constraint could not be satisfied.` で失敗する。現行 `typeCheckClassLikeMembers` は source-order pass 後に member function を再チェックするが、最初の pass で property type 解決前の診断が確定し、二度目の pass で回復できない。全 property type の副作用安全な prepass、または参照時の遅延解決と診断 defer が必要。PR #4632 の conflict repair 中にレビュー由来の再現を現行 `master` で再確認

### Diff skip 追跡（残り 6 件）
> 2026-07-14 棚卸し: [`docs/diff-skip-inventory.md`](docs/diff-skip-inventory.md)。現時点の `DEBT-DIFF-*` タグ付き skip は 120 件（001:19 / 002:4 / 003:12 / 004:0（解消済み） / 005:6 / 006:3 / 007:76）。実測値は `find Scripts/diff_cases -type f \( -name '*.kt' -o -name '*.kts' \) -print0 | xargs -0 rg -o 'DEBT-DIFF-[0-9]{3}' -N | sort | uniq -c` で確認。各タスクの完了条件は、該当ケースを通常 `diff_kotlinc.sh` に戻すか、JVM kotlinc を oracle にできない理由と代替 runner / unit test owner を同文書へ移すこと。
- [ ] DEBT-DIFF-001: `Scripts/diff_cases` のうち JVM kotlinc reference では実行不能な target / classpath / runtime-only ケースを、diff harness の除外理由として維持するか、個別 runner / dependency injection で実行可能化するか棚卸しする。対象: Kotlin/Native・Kotlin/JS・KMP・`kotlin.io.path`・JDBC/SQLite・serialization・SLF4J/logging・system time/process API・assert JVM `-ea` 差分・compiler plugin API。
- [ ] DEBT-DIFF-002: script-style diff cases の top-level execution parity / stdlib nondeterminism を整理し、script runner 側で安定比較できるケースから `SKIP-DIFF` を外す。（2026-07-09: kotlinc JVM 起動 timeout 起因だった3件は `--script-timeout` 分離で解除済み。残り5件は timeout とは別要因）
- [ ] DEBT-DIFF-003: advanced coroutine / channel / Flow / structured concurrency diff cases を `STDLIB-CORO-001` と `DEBT-CORO-002/003` の残課題へ分解し、実装済み API から順に skip を解除する。2026-07-10: `coroutine_deferred.kt`/`coroutine_structured_concurrency.kt`/`coroutine_supervisor_job.kt` 着手。Sema側の一般的バグ5件を修正（`kotlin.coroutines` default import欠落・`IntRange.map`要素型破壊・`async`/`coroutineScope`/`supervisorScope`戻り値型narrowing欠如・ラムダ本体のUnit-coercion時にexpectedTypeを誤伝播して`repeat`等が"No viable overload"になるバグ）、19ケースで回帰なし確認済み。ただし各ケースにKIR/runtime層の別バグが残存: (a) Iterator経由で取得したDeferred/Jobに`.await()`するとSIGSEGV、(b) `coroutineScope{}`が外側可変変数をキャプチャするとlowering失敗（`launch`/`async`は正常）、(c) `SupervisorJob()`/`CoroutineScope(context)`未実装。詳細は `docs/diff-skip-inventory.md` の「structured concurrency / Deferred / Supervisor 詳細」節参照。
- [ ] DEBT-DIFF-005: common stdlib surface gap による skip（Sequence flatten/takeLast/subtract、scope functions、property delegates、Regex edge cases、ByteArray helpers、file.use、Duration/time、math/comparator APIs、Random.nextFloat range overload/nextBytes）を API 領域別タスクへ分割し、実装済みケースから skip を解除する。BigInteger は `not`/`shiftLeft`/`shiftRight` の未登録と shiftLeft/shiftRight のエンディアン不整合バグを修正し、skip 解除済み。
- [ ] DEBT-DIFF-006: type inference / variance / boxed numeric lowering 由来の diff skip を、診断期待ケースまたは parity regression として実行可能な形へ分解する。2026-07-09: `error_type_inference.kt` を解析し diff_cases から削除済み（下記「Sema 型推論診断ギャップ」節を参照）。現在の残存対象は `compiler_plugin_api.kt` と `math_rounding_functions.kt`。

- [ ] DEBT-DIFF-007: `run_case` の compile-exit-code-match 誤判定修正（2026-07-08、`Scripts/diff_kotlinc.sh`）で新規に顕在化した ref/candidate 不一致 76 件を棚卸し済み（`docs/diff-skip-inventory.md` の DEBT-DIFF-007 節）。診断/ネガティブテスト・enum/data class/interface 未実装・common stdlib gap・coroutine Flow・reflection・JVM interop・finally routing の7グループへ分解済みなので、グループ単位で実装 owner へ割り当てて skip を解除する。

#### Sema 型推論診断ギャップ（直上項目の分析から判明、2026-07-09）
> `error_type_inference.kt` を diagnostics golden へ移設しようとしたところ、5 シナリオ全てで kswiftc が診断を1件も出さないことが判明した。JVM kotlinc 2.4.0 で裏取りした結果、3 件は本物のコンパイルエラー（kswiftc 側の Sema 検出漏れ）、残り 2 件（`identity(null)` の T 推論、expected-type 駆動の `produce(): T`）はそもそも正当な Kotlin コードで元の想定コメントが誤りだった。検出漏れの 3 件は `Tests/CompilerCoreTests/Sema` に `assertNoDiagnostic` ベースの回帰テストとして現状を固定済み — Sema 修正時にテストが失敗して気づける。
- [ ] DEBT-SEMA-001: 未注釈オーバーロードで、ラムダ引数の暗黙 `it` パラメータ型がオーバーロード解決前に確定できず曖昧になるケース（`fun process(block: (Int) -> String)` / `fun process(block: (String) -> Int)` を `process { it }` で呼ぶ等）を `KSWIFTK-SEMA-0003` で検出できるようにする。回帰テスト: `OverloadResolutionByLambdaReturnTypeTests.testImplicitItParameterOverloadAmbiguityIsNotYetDetected`
- [ ] DEBT-SEMA-002: `where T : ClassA, T : ClassB` のように型パラメータの upper bound に相互排他的な複数クラスが指定された宣言を検出する（宣言サイトの bound 整合性チェック。呼び出しサイトの `KSWIFTK-SEMA-BOUND` とは別軸）。回帰テスト: `TypeConstraintBoundsTests.testConflictingClassUpperBoundsAreNotYetDetected`
- [ ] DEBT-SEMA-003: トップレベル `val` の初期化子が自分自身を参照する場合（`val cyclic: List<*> = listOf(cyclic)`）を「初期化前に使用された変数」として検出する。回帰テスト: `DataFlowAndSemaRegressionTests.testSelfReferentialTopLevelInitializerIsNotYetDetected`

### ドキュメント乖離
- [x] DEBT-DOC-001: `README.md` / `CLAUDE.md` の Swift toolchain 表記を実態（`Package.swift` は `swift-tools-version: 6.2` / `swiftLanguageModes: [.v6]`）へ同期する
- [x] DEBT-DOC-002: `docs/ARCHITECTURE.md` §4 の KIR テーブルへ未記載の実在ファイルを追記する（`CallSupportLowerer` / `ObjectLiteralLowerer` / `KIRLoweringContext` / `ConstantCollector` / `LateinitReadWrapping` / `KClassAnnotationRegistrationLowering` / `MutableCaptureCellHelpers` / `RuntimeTypeCheckToken` 等。architecture sync 済み範囲はモジュール構成・CI 表のみでファイルテーブルは未カバー）
- [x] DEBT-DOC-003: `docs/ARCHITECTURE.md` §10 の Lowering パス実行順序へ未記載の実在パスを実行順付きで追記する（`EnumEntriesLoweringPass` / `EnumNameAccessLoweringPass` / `FlowLoweringPass` / `IntegerNarrowingPass` / `JvmOverloadsLoweringPass` / `JvmStaticLoweringPass` / `TailrecLoweringPass` / `ValueClassUnboxingPass`）
- [x] DEBT-DOC-004: `docs/ARCHITECTURE.md` の「CoroutineLoweringPass (+分割3ファイル)」を実態（`+Analysis` / `+CallRewriting` / `+Flow` / `+FlowInstructionRewrite` / `+LauncherSupport` / `+StateMachine` / `+Synthesis` の 7 分割・計 8 ファイル）へ修正する。2026-07-10 完了: §9 に `CoroutineLoweringPass.swift` 本体 + 7 extension ファイルの構成を明記。

## Dead Code 削除タスク（DEADCODE: 2026-07-11〜12 再監査）

> 2026-06-12 監査分の履歴は [`docs/dead-code-audit.md`](docs/dead-code-audit.md) に保存。今回は現 HEAD で (1) Swift の USR/index 解析（Periphery 3.7.4、public/Codable は保持）、(2) 識別子の宣言・呼び出し箇所の `rg` 照合、(3) 2,791 件の Runtime `@_cdecl`（`kk_*` 2,739 件 + `__kk_*` 52 件）に対する CompilerCore / CompilerBackend / bundled Kotlin / Runtime 内部 / Tests / ABI テーブル経路の照合、を併用した。
> 根拠略号: **R0** = 宣言以外の参照 0、**D** = 参照元が別の dead symbol のみ、**W0** = 代入/初期化のみで read 0、**E0** = Runtime export に emit/内部/テスト経路 0、**T** = 製品からは未使用でテストのみ。同名 overload や別 lexical scope は USR 単位で分離済み。
> 1 checkbox = 1 method / property / type / enum case を原則とする。D 項目は参照元タスクを先に削除し、最後に owner type/file を整理する。`RuntimeABISpec` 登録は使用証拠ではないため、E0 削除時は spec/parity/snapshot も同時に消す。
> 除外を実済み: `kk_print_string_flat` は Backend が直接 emit するため alive。`kk_atomic_*` は prefix + suffix の 2 段階動的生成、URLSession delegate / `@main` / XCTest・Swift Testing discovery / protocol witness / Hashable・Codable 合成参照も alive として除外。
> 完了ゲートは refactor PR gate（全テスト + golden + `diff_kotlinc.sh` green）。完全に到達不能な単独 private helper のみを削除する PR は、対象 module テスト + `git diff --check` を最低ゲートとし、まとめ PR 時に full gate を実施する。

### 監査基盤 / 残領域

- [ ] DEADCODE-AUDIT-001: `Scripts/dead_code_audit.sh` の export 対象を `kk_*` だけでなく `__kk_*` にも広げ、static emit 検索を CompilerCore 限定から CompilerBackend / bundled `.kt` まで拡張し、`prefix` 変数 + `"\(prefix)_suffix"` の 2 段階生成も解決する。現状は `kk_print_string_flat` を A に誤分類し、Atomic 群を B に大量誤分類する。回帰 fixture を各 1 件追加する
- [~] DEADCODE-014: 旧「未監査領域」を継続監査する。2026-07-12 時点で tracked `.c/.h/.cc/.cpp` は 0 件、`DiagnosticRegistry` 108 descriptor は全て production 発行箇所あり、stored/global/Tests helper の検出結果は下記に分割済み。残りは SKIP-DIFF 62 件の実行可否。`compiler_plugin_api.kt` は強制実行で kotlinc timeout + kswiftc 型/抽象メンバ解決失敗のため解除不可を確認済み

### CompilerCore: 参照ゼロの独立シンボル

- [ ] DEADCODE-CORE-001: [R0] `HeaderHelpers+SyntheticNativeInteropHelpers.swift:62` の private `syntheticListType(elementType:symbols:types:interner:)` を削除する。別ファイルの同名 private helper は別 USR
- [x] DEADCODE-CORE-002: [R0] `BuildASTPhase+DeclBuilders.swift:654` の private `skipLeadingAnnotations(in:)` を削除する。2026-07-16 完了: 参照ゼロを確認し削除、Golden green
- [ ] DEADCODE-CORE-003: [R0] `CallLowerer+CollectionStdlibMemberCalls.swift:5` の `tryLowerCollectionStdlibMemberCall(...)` を削除する（1,336 行の orphan legacy entrypoint）
- [x] DEADCODE-CORE-004: [R0] `CallLowerer+PrimitiveMemberCalls.swift:5` の `tryLowerPrimitiveMemberCall(...)` を削除する（668 行の orphan legacy entrypoint）— ファイル自体を削除。定義以外の参照ゼロを grep で確認済み。内部から呼んでいたヘルパー（`shouldLowerPrimitiveInv` 等）は他ファイルからも呼ばれておりそのまま残置
- [ ] DEADCODE-CORE-005: [R0] `CallLowerer+StringBuilderMemberCalls.swift:5` の `tryLowerStringBuilderMemberCall(...)` を削除する（240 行の orphan legacy entrypoint）
- [x] DEADCODE-CORE-006: [R0] `CallLowerer+StringStdlibMemberCalls.swift:53` の `tryLowerStringStdlibMemberCall(...)` を削除する。先頭の live `tryLowerTableDrivenStringMemberCall` は残す
- [x] DEADCODE-CORE-007: [D: CORE-006] `CallLowerer+StringStdlibMemberCalls.swift:1355` 内 local `boxedFormatArgument(_:loweredArgID:)` を削除する。呼び出しは dead parent 内のみ
- [ ] DEADCODE-CORE-008: [R0] `HeaderHelpers+SyntheticCoroutineRegistry.swift:2522` の `registerSyntheticCoroutinesABIStubs(...)` を削除する。`STDLIB-CORO-ABI-001` surface がまだ必要なら、削除ではなく live registry へ配線して本 ID を閉じる
- [ ] DEADCODE-CORE-009: [R0] `HeaderHelpers+SyntheticDynamicStubs.swift:4` の `registerSyntheticDynamicStubs(...)` を削除する（Native 対象外の Kotlin/JS surface）
- [ ] DEADCODE-CORE-010: [D: CORE-009] 同ファイル `:42` の private `registerDynamicIterator(...)` を削除する
- [ ] DEADCODE-CORE-011: [R0] `HeaderHelpers+SyntheticFileIOStubs.swift:1937` の private `registerKotlinIOExtensionProperty(...)` を削除する
- [ ] DEADCODE-CORE-012: [R0] `HeaderHelpers+SyntheticJsArrayExternalClassStubs.swift:7` の `registerSyntheticJsArrayExternalClassStubs(...)` を削除する
- [ ] DEADCODE-CORE-013: [R0] `HeaderHelpers+SyntheticJsArrayStubs.swift:4` の `registerSyntheticJsArrayStubs(...)` を削除する
- [ ] DEADCODE-CORE-015: [D: CORE-014] 同ファイル `:49` の private `ensureJsStringInterface(...)` を削除する
- [ ] DEADCODE-CORE-016: [D: CORE-014] 同ファイル `:88` の private `registerStringToJsStringExtension(...)` を削除する
- [ ] DEADCODE-CORE-018: [R0] `HeaderHelpers+SyntheticMetaprogAnnotationHelpers.swift:118` の `registerSyntheticJvmAnnotationClass(...)` を削除する
- [x] DEADCODE-CORE-019: [R0] 同ファイル `:863` の `registerSyntheticBooleanAnnotationPropertyAndConstructor(...)` を削除する。2026-07-17 完了: `registerSyntheticBooleanAnnotationPropertyAndConstructor` は宣言以外の参照ゼロ（リポジトリ全体を `grep` 照合、呼び出し元なし）を確認し削除。同ファイル内の `registerSyntheticStringAnnotationPropertyAndConstructor` 等の姉妹関数は他から呼ばれておりそのまま残置。`swift build` 成功・`git diff --check` クリーンを確認済み。`CompilerCoreTests` フルスイートは同時 8〜16 worktree・load average 25〜246・空きメモリ数百MB/swap 0 の高負荷環境下で `swiftpm-testing-helper` が signal 10 (SIGBUS) で複数回異常終了し完走不可（worker 数を 14→4 に絞っても再発、対象コード変更とは無関係の環境要因と判断）。変更箇所を直接カバーする `CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden`（worker 数 2）は 297/297 green を確認済み
- [ ] DEADCODE-CORE-020: [R0] `HeaderHelpers+SyntheticPropertyDelegateStubs.swift:2523` の `registerSyntheticKPropertyIsInitializedStub(...)` を削除する
- [ ] DEADCODE-CORE-022: [R0] `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift:629` の `registerSyntheticEmptyCollectionFunction(...)` を削除する
- [x] DEADCODE-CORE-023: [R0] `HeaderHelpers+SyntheticW3CDomStubs.swift:3` の `registerSyntheticW3CDomStubs(...)` を削除する。2026-07-17 完了: 宣言以外の参照ゼロを再確認し、CORE-024 と合わせてファイルごと削除
- [x] DEADCODE-CORE-024: [D: CORE-023] 同ファイル `:28` の private `registerItemArrayLike(...)` を削除する。2026-07-17 完了: 唯一の呼び出し元は CORE-023 の `registerSyntheticW3CDomStubs` のみで他に参照なし。ファイルが空になるため `HeaderHelpers+SyntheticW3CDomStubs.swift` ごと削除
- [ ] DEADCODE-CORE-025: [R0] `SyntheticStubSurfaceSpec+NativeRefRuntime.swift:109` の `debuggingType` を削除する。Debugging object 登録側は owner type を手作業で再構築しており本 property を読まない
- [ ] DEADCODE-CORE-026: [R0] `SemanticsModels.swift:1013` の private `areKindsCompatibleForExpectActual(expect:actual:)` を削除する
- [ ] DEADCODE-CORE-027: [R0] `CallTypeChecker+MemberCallInferenceFallbacks.swift:386` の `isKotlinDurationType(_:sema:interner:)` を削除する
- [x] DEADCODE-CORE-028: [R0] `CallTypeChecker+SyntheticDispatchHelpers.swift:187` の `shouldUseRuntimeStdlibSpecialCall(...)` を削除する。2026-07-17 完了: 宣言以外の参照ゼロ（リポジトリ全体 `rg` で再確認）を確認し関数本体とドキュメントコメントを削除。`swift build` 成功・`git diff --check` クリーン・`--filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden`（297件）と `--filter CompilerCoreTests.TypeCheckHelpersCoverageTests`（7件）が "All tests passed." で green を確認済み。フル `--filter CompilerCoreTests` は本タスクとは無関係な既存の環境要因クラッシュ（BUG-045）に3回とも巻き込まれ完走しなかったため、影響範囲に絞った上記2スイートを代替エビデンスとした
- [ ] DEADCODE-CORE-029: [R0] `BundledDeclarationIndex.swift:67` の `build(symbols:types:sourceManager:interner:)` overload を削除する。`Phase.swift` が使う `build(ast:symbols:types:sourceManager:interner:)` は残す
- [x] DEADCODE-CORE-030: [R0] `TypeInferenceContext.swift:80` の `with(enclosingClassSymbol:)` を削除する。`copying(...enclosingClassSymbol:)` は別 API として残す。2026-07-17 完了: `rg` で宣言以外の呼び出しゼロを確認し削除、`copying(enclosingClassSymbol:)` 経由の呼び出し（`DeclTypeChecker+ClassAndObjectChecking.swift` 等）は変更なし。`swift build` 成功、Sema ゴールデン含むテストで回帰なしを確認
- [x] DEADCODE-CORE-031: [R0] `SyntheticStubSurfaceSpec.swift:18` の static `float` 型参照定数を削除する
- [ ] DEADCODE-CORE-032: [R0] `SyntheticStubSurfaceSpec.swift:21` の static `uint` 型参照定数を削除する
- [x] DEADCODE-CORE-033: [R0] `SyntheticStubSurfaceSpec.swift:22` の static `ulong` 型参照定数を削除する。2026-07-17 完了: `SyntheticStubTypeRef.ulong` は宣言以外の参照ゼロ（呼び出し元 4 ファイル — `HeaderHelpers+SyntheticExceptionStubs.swift` / `+SyntheticIteratorStubs.swift` / `+SyntheticCharStubs.swift` / `SyntheticStubSurfaceSpec+NativeRefRuntime.swift` — で `.ulong` 未使用と確認済み、テストからの直接参照もなし）を確認し削除。`SyntheticStubBuiltinType.ulong` ケースと `resolveSyntheticStubBuiltinType` 内の対応 switch アームは、`.error`/`.nothing` 同様に convenience `static let` を持たない他ケースと同型の型ボキャブラリ定義のため残置。`swift build` 成功・`git diff --check` クリーン・`CompilerCoreTests` green を確認済み
- [x] DEADCODE-CORE-034: [R0] `SyntheticStubSurfaceSpec.swift:23` の static `ubyte` 型参照定数を削除する。2026-07-17 完了: `rg`で全ソース照合し宣言以外の参照ゼロを再確認して削除（`SyntheticStubBuiltinType.ubyte` enum case と `resolveSyntheticStubBuiltinType` 内の対応 case は exhaustive switch 維持のため残置、対象外）。`swift build` green。並列フルテストで `CompilerBackendTests` 17件のタイムアウトと Golden 実行中の `swiftpm-testing-helper` SIGBUS クラッシュが発生したが、いずれも ubyte/UByte 非依存かつ本変更と無関係の箇所（Int算術・コンストラクタ委譲等）で、直列再実行（`SWIFT_TEST_PARALLEL=0`）では `CompilerBackendTests` 全937件・Golden全13件/6スイートとも green となり、高負荷時の環境要因（既存 flaky 傾向、BUG-039系）による偽陽性と確認済み。`git diff --check` green。`diff_kotlinc.sh` は本変更が実行時コードパスに影響しない（宣言のみの削除）ため未実施
- [ ] DEADCODE-CORE-035: [R0] `SyntheticStubSurfaceSpec.swift:24` の static `ushort` 型参照定数を削除する
- [ ] DEADCODE-CORE-036: [W0] `CompilerKnownNames.swift:393` の `kotlinRunCatchingFQName` を削除し、initializer `:597` の代入も消す
- [ ] DEADCODE-CORE-037: [W0] `CollectionLiteralLoweringPass+LookupTables.swift:487` の `filterIsInstanceName` と initializer `:1288` の代入を削除する
- [ ] DEADCODE-CORE-039: [W0] 同ファイル `:750` の `kkPathGetName` と initializer `:1541` の代入を削除する
- [x] DEADCODE-CORE-040: [W0] 同ファイル `:771` の `maxDepthName` と initializer `:1562` の代入を削除する。2026-07-17 完了: 宣言・初期化とも他に参照なしを確認の上削除、`swift build` green
- [ ] DEADCODE-CORE-041: [W0] 同ファイル `:774` の `onEnterName` と initializer `:1565` の代入を削除する
- [ ] DEADCODE-CORE-042: [W0] 同ファイル `:776` の `onLeaveName` と initializer `:1567` の代入を削除する
- [x] DEADCODE-CORE-043: [W0] 同ファイル `:778` の `onFailName` と initializer `:1569` の代入を削除する
- [ ] DEADCODE-CORE-044: [R0/local] `CoroutineLoweringPass+Flow.swift:198` の local `isSymbolBackedFlowExpr(_:)` を削除する。別ファイルの同名 local は live
- [x] DEADCODE-CORE-045: [R0/local] `CoroutineLoweringPass+FlowInstructionRewrite.swift:51` の local `isFlowTransformEmitCall(_:_:)` を削除する。`CoroutineLoweringPass+Flow.swift` の同名 local は live

### CompilerCore: ReceiverClassifier 統合後の残存

- [x] DEADCODE-CORE-046: [R0] `ReceiverClassifier.swift:91` の `ReceiverClassifier.isSequenceLikeReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-047: [R0] 同ファイル `:129` の `ReceiverClassifier.isMapLikeCollectionReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-048: [R0] 同ファイル `:170` の `ReceiverClassifier.isMutableListCollectionReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-049: [R0] 同ファイル `:209` の `ReceiverClassifier.isConcreteListLikeCollectionReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-050: [R0] 同ファイル `:221` の `ReceiverClassifier.isSetLikeCollectionReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-051: [D: CORE-052] 同ファイル `:68` の `ReceiverClassifier.isCollectionLikeReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-052: [R0] 同ファイル `:331` の `CallTypeChecker.isCollectionLikeReceiver(receiverID:sema:interner:)` forwarding overload を削除する
- [x] DEADCODE-CORE-053: [D: CORE-054] 同ファイル `:141` の `ReceiverClassifier.isMutableListType(_:)` を削除する
- [x] DEADCODE-CORE-054: [R0] 同ファイル `:315` の `CallTypeChecker.isMutableListType(_:sema:interner:)` forwarding overload を削除する
- [x] DEADCODE-CORE-055: [R0] 同ファイル `:150` の `ReceiverClassifier.isMutableCollectionReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-056: [R0] 同ファイル `:185` の `ReceiverClassifier.isMutableSetReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-057: [R0] 同ファイル `:197` の `ReceiverClassifier.isMutableMapReceiver(receiverID:)` を削除する
- [x] DEADCODE-CORE-058: [R0] 同ファイル `:323` の `CallTypeChecker.isMapLikeCollectionType(_:sema:interner:)` forwarding overload を削除する。Classifier 側の型判定本体は live
- [x] DEADCODE-CORE-059: [R0] 同ファイル `:339` の `CallTypeChecker.isIterableLikeReceiver(receiverID:sema:interner:)` forwarding overload を削除する。Classifier 側は live
- [x] DEADCODE-CORE-060: [R0] 同ファイル `:371` の `CallTypeChecker.isListCollectionFactoryReceiver(receiverID:ast:sema:interner:)` forwarding overload を削除する。Classifier 側は live
- [x] DEADCODE-CORE-061: [D: CORE-053] 同ファイル `:285` の private `nominalSymbol(of:)` を削除する
- [x] DEADCODE-CORE-062: [R0] 同ファイル `:327` の `CallTypeChecker.isConcreteListLikeType(_:sema:interner:)` forwarding overload を削除する
- [x] DEADCODE-CORE-063: [W0] `ReceiverClassification.receiverType` (`ReceiverClassifier.swift:2`) を削除し、`classify` の初期化引数 `:39` も消す。判定フラグ群は残す。2026-07-21 完了: 対象 API 18件を削除。`swift build` 成功、`ListSyntheticMemberLinkTests` 120件成功、対象 API の残存参照なし、`git diff --check` clean を確認

### CompilerCore: ABI / boxing の未参照 alias・overload

- [x] DEADCODE-CORE-064: [R0] `ABILoweringPass.swift:5` の `primitiveBoxingCalleeNamesByPrimitive` alias を削除する
- [x] DEADCODE-CORE-065: [R0] 同ファイル `:6` の `primitiveUnboxingCalleeNamesByPrimitive` alias を削除する
- [x] DEADCODE-CORE-066: [R0] 同ファイル `:8` の `primitiveBoxingCalleeNames` alias を削除する
- [x] DEADCODE-CORE-067: [R0] 同ファイル `:9` の `primitiveUnboxingCalleeNames` alias を削除する
- [x] DEADCODE-CORE-068: [R0] 同ファイル `:19` の `primitiveBoxingCalleeName(for: TypeKind)` overload を削除する
- [x] DEADCODE-CORE-069: [R0] 同ファイル `:23` の `primitiveUnboxingCalleeName(for: TypeKind)` overload を削除する
- [x] DEADCODE-CORE-070: [R0] 同ファイル `:41` の `primitiveBoxingCallee(for: TypeKind, interner:)` overload を削除する
- [x] DEADCODE-CORE-071: [D: CORE-066] `BoxingCalleeTable.swift:66` の `primitiveBoxingCalleeNames` set を削除する
- [x] DEADCODE-CORE-072: [D: CORE-067] 同ファイル `:67` の `primitiveUnboxingCalleeNames` set を削除する
- [x] DEADCODE-CORE-073: [D: CORE-068] 同ファイル `:104` の `boxCalleeName(for: TypeKind, requireNonNull:)` overload を削除する
- [x] DEADCODE-CORE-074: [D: CORE-069] 同ファイル `:111` の `unboxCalleeName(for: TypeKind, requireNonNull:)` overload を削除する
- [x] DEADCODE-CORE-075: [T] `ABILoweringPass.swift:11` の `primitiveBoxingCalleeName(for: PrimitiveType)` wrapper を削除し、`BoxingCalleeTableTests.swift:25` の重複 assertion を本体 table 検証へ統合する
- [x] DEADCODE-CORE-076: [T] `ABILoweringPass.swift:15` の `primitiveUnboxingCalleeName(for: PrimitiveType)` wrapper を削除し、`BoxingCalleeTableTests.swift:26` の重複 assertion を本体 table 検証へ統合する

  - 2026-07-21 完了: `ABILoweringPass` の未参照 alias／wrapper／`TypeKind` boxing overload、`BoxingCalleeTable` の依存 set／name overload を削除。primitive table の検証は `BoxingCalleeTableTests` 本体へ統合し、focused test 2件が green。

### CompilerBackend: 未生成 `FunctionEmissionState` クラスタ

> `rg 'FunctionEmissionState\s*\(' Sources Tests` は 0 件。現行パスは `NativeEmitter+FunctionEmission.swift` の monolithic `emitFunctionBody` を使う。まず root 呼び出しを削除し、D ヘルパを順次消し、最後に owner type と 3 ファイルを削除する。

- [x] DEADCODE-BACKEND-001: [R0] `NativeEmitter+InstructionEmission.swift:7` の `FunctionEmissionState.emitInstruction(...)` を削除する
- [x] DEADCODE-BACKEND-002: [D: BACKEND-001] `NativeEmitter+CallEmission.swift:8` の `emitCallInstruction(...)` を削除する
- [x] DEADCODE-BACKEND-003: [D: BACKEND-001] 同ファイル `:332` の `emitVirtualCallInstruction(...)` を削除する
- [x] DEADCODE-BACKEND-004: [D: BACKEND-001] `NativeEmitter+InstructionEmission.swift:285` の private `updateDebugLocation(...)` を削除する
- [x] DEADCODE-BACKEND-005: [D: BACKEND-001] 同ファイル `:323` の private `emitConstValueDebugInfo(...)` を削除する
- [x] DEADCODE-BACKEND-006: [D: BACKEND-001] 同ファイル `:392` の private `emitNullAssert(...)` を削除する
- [x] DEADCODE-BACKEND-007: [D: BACKEND-001] `NativeEmitter+FunctionEmissionState.swift:84` の `assignmentTargets(for:)` を削除する。live な同名 local function は別 USR
- [x] DEADCODE-BACKEND-008: [D] 同ファイル `:114` の `declareExternalFunction(...)` を削除する
- [x] DEADCODE-BACKEND-009: [D] 同ファイル `:150` の `resolveUnnamedInternalFunction(...)` を削除する
- [x] DEADCODE-BACKEND-010: [D] 同ファイル `:173` の `valueForConstant(_:expressionRawID:)` を削除する
- [x] DEADCODE-BACKEND-011: [D] 同ファイル `:189` の `resolveValue(_:)` を削除する
- [x] DEADCODE-BACKEND-012: [D] 同ファイル `:204` の `rawComparableValues(lhs:rhs:)` を削除する
- [x] DEADCODE-BACKEND-013: [D] 同ファイル `:228` の `storeResult(_:_:)` を削除する
- [x] DEADCODE-BACKEND-014: [D] 同ファイル `:245` の `blockForLabel(_:)` を削除する
- [x] DEADCODE-BACKEND-015: [D] 同ファイル `:256` の `buildThrownSlotCondition(from:name:)` を削除する
- [x] DEADCODE-BACKEND-016: [D] 同ファイル `:263` の `storeOutThrownIfNonNull(_:suffix:)` を削除する
- [x] DEADCODE-BACKEND-017: [D] 同ファイル `:303` の `emitFramePop(_:)` を削除する
- [x] DEADCODE-BACKEND-018: [D] 同ファイル `:316` の `emitBuiltinCall(...)` を削除する。live な同名 local function は別 USR
- [x] DEADCODE-BACKEND-019: [R0] 同ファイル `:335` の `setupFrame(function:)` を削除する
- [x] DEADCODE-BACKEND-020: [D: BACKEND-021〜050] `NativeEmitter+FunctionEmissionState.swift:39` の `FunctionEmissionState.init(...)` を削除する
- [x] DEADCODE-BACKEND-021: [D] 同ファイル `:5` の stored property `emitter` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-022: [D] 同ファイル `:6` の stored property `builder` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-023: [D] 同ファイル `:7` の stored property `int64Type` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-024: [D] 同ファイル `:8` の stored property `zeroValue` を削除し、initializer の property assignment も消す
- [x] DEADCODE-BACKEND-025: [D] 同ファイル `:9` の stored property `context` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-026: [D] 同ファイル `:10` の stored property `llvmModule` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-027: [D] 同ファイル `:11` の stored property `llvmFunction` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-028: [D] 同ファイル `:12` の stored property `outThrownPointerType` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-029: [D] 同ファイル `:13` の stored property `outThrownParameter` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-030: [D] 同ファイル `:14` の stored property `nullThrownPointer` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-031: [D] 同ファイル `:15` の stored property `parameterValues` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-032: [D] 同ファイル `:16` の stored property `internalFunctions` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-033: [D] 同ファイル `:17` の stored property `globalVariables` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-034: [D] 同ファイル `:18` の stored property `maxKIRArgumentCountByExternalCallee` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-035: [D] 同ファイル `:19` の stored property `builderState` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-036: [D] 同ファイル `:20` の stored property `copyTargetAllocas` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-037: [D] 同ファイル `:22` の stored property `framePopFunction` を削除する
- [x] DEADCODE-BACKEND-038: [D] 同ファイル `:23` の stored property `coroutineRegisterRootFunction` を削除する
- [x] DEADCODE-BACKEND-039: [D] 同ファイル `:24` の stored property `coroutineUnregisterRootFunction` を削除する
- [x] DEADCODE-BACKEND-040: [D] 同ファイル `:25` の stored property `functionIDValue` と initializer `:77` の初期化を削除する
- [x] DEADCODE-BACKEND-041: [D] 同ファイル `:27` の stored property `currentBlock` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-042: [D] 同ファイル `:28` の stored property `values` を削除する
- [x] DEADCODE-BACKEND-043: [D] 同ファイル `:29` の stored property `rawResultValues` を削除する
- [x] DEADCODE-BACKEND-044: [D] 同ファイル `:30` の stored property `externalFunctions` を削除する
- [x] DEADCODE-BACKEND-045: [D] 同ファイル `:31` の stored property `labelBlocks` を削除し、initializer parameter / assignment も消す
- [x] DEADCODE-BACKEND-046: [D] 同ファイル `:32` の stored property `generatedStringLiteralCount` を削除する
- [x] DEADCODE-BACKEND-047: [D] 同ファイル `:34` の computed property `bindings` を削除する
- [x] DEADCODE-BACKEND-048: [D] 同ファイル `:35` の computed property `module` を削除する
- [x] DEADCODE-BACKEND-049: [D] 同ファイル `:36` の computed property `interner` を削除する
- [x] DEADCODE-BACKEND-050: [D] 同ファイル `:37` の computed property `sourceManager` を削除する
- [x] DEADCODE-BACKEND-051: [R0/type; 前提 BACKEND-001〜050] `NativeEmitter.FunctionEmissionState` (`NativeEmitter+FunctionEmissionState.swift:4`) と、空になる `NativeEmitter+FunctionEmissionState.swift` / `NativeEmitter+CallEmission.swift` / `NativeEmitter+InstructionEmission.swift` を削除する
- [x] DEADCODE-BACKEND-052: [R0] `NativeEmitter.swift:424` の private `emitFunctionBodiesParallel(...)` を削除する。parallel codegen は `:361` のコメントどおり disabled、local type `ParallelEmissionWork` も本 body と同時に消す
- [x] DEADCODE-BACKEND-053: [W0] `NativeEmitter.swift:308` の local `functionDeclInfo` と `:356` の append を削除する。同名の後続参照は dead parallel method の別 parameter/field
- [x] DEADCODE-BACKEND-054: [D: BACKEND-052] `LLVMCAPIBindings+Core.swift:126` の `linkModules(_:source:)` を削除する。唯一の caller は dead parallel emission body

> 2026-07-21 完了: `FunctionEmissionState` とその call/instruction emission extension、無効化済み parallel codegen、専用の LLVM module linker helper/binding を削除。現行の `NativeEmitter+FunctionEmission.swift` の serial emission path は維持する。
> 検証: Xcode beta toolchain の `swift build`、`VirtualDispatchCodegenTests.testLLVMBackendCompilesVirtualCallWithoutError` 1/1、`RuntimeStubImplementationTests` 1/1、`KotlinCompilationObjectEmissionTests` 10/10 が成功。`CompilerBackendTests` 全体は `LinkPhase.swift:109` の既存 `outputUnavailable` が実行系ケースで再発したため中断（KIR/ABI ケースは通過）。

### Runtime: 完全到達不能 export / legacy bridge

- [ ] DEADCODE-RUNTIME-001: [E0] `RuntimeStringArray.swift:2120` の `kk_readln_from_syscall(_:)` を削除し、`RuntimeABISpec+IO.swift:28` の spec も消す。現行 IO は `kk_readline` / `kk_readln` / `kk_readlnOrNull`
- [ ] DEADCODE-RUNTIME-002: [E0] `RuntimeStringStdlib.swift:117` の `kk_string_capitalize(_:)` を削除し、`RuntimeABISpec+String.swift:1007` も消す。source-backed 実装は既存で external link nil（KSP-412 の子タスク）
- [ ] DEADCODE-RUNTIME-003: [E0] `RuntimeStringHOF.swift:1355` の `kk_string_onEach_flat(...)` を削除する。raw `kk_string_onEach` は compiler emit + ABI spec ありのため残す
- [ ] DEADCODE-RUNTIME-004: [E0] `RuntimeStringHOF.swift:1561` の `kk_string_onEachIndexed_flat(...)` を削除する。raw 版は残す
- [ ] DEADCODE-RUNTIME-005: [E0] `RuntimeStringConversion.swift:603` の `__kk_string_toBigDecimalOrNull_flat(...)` を削除する。raw `__kk_string_toBigDecimalOrNull` は bundled source / compiler fallback / runtime test から到達するため残す
- [ ] DEADCODE-RUNTIME-006: [E0] `RuntimeStringConversion.swift:644` の `__kk_string_toBigIntegerOrNull_flat(...)` を削除する。raw `__kk_string_toBigIntegerOrNull` は bundled source / compiler fallback / runtime test から到達するため残す
- [ ] DEADCODE-RUNTIME-007: [E0] `RuntimeStringArray.swift:2113` の `kk_sys_write(_:_:_:)` を削除し、`RuntimeABISpec+System.swift:97` も消す。console IO は Swift `print` / `readLine` 経路
- [ ] DEADCODE-RUNTIME-008: [E0] `RuntimeStringStdlib.swift:237` の raw `__kk_string_normalize` を削除する。旧 `ABIMismatchTests+NonThrowingParity.swift` の legacy snapshot は f922ed768b で削除済み。live な `_flat` 版は残す
- [ ] DEADCODE-RUNTIME-009: [E0] `RuntimeStringStdlib.swift:262` の raw `__kk_string_isNormalized` を削除する。旧 `ABIMismatchTests+NonThrowingParity.swift` の legacy snapshot は f922ed768b で削除済み。live な `_flat` 版は残す
- [ ] DEADCODE-RUNTIME-010: [E0] `RuntimeStringFormat.swift:694` の `__string_trimIndent` と `RuntimeABISpec+String.swift:3025` の spec を削除する（KSP-302 後始末）
- [ ] DEADCODE-RUNTIME-011: [E0] `RuntimeStringFormat.swift:699` の `__string_trimMargin` と `RuntimeABISpec+String.swift:3033` の spec を削除する
- [ ] DEADCODE-RUNTIME-012: [E0] `RuntimeStringFormat.swift:704` の `__string_prependIndent` と `RuntimeABISpec+String.swift:3042` の spec を削除する
- [ ] DEADCODE-RUNTIME-013: [E0] `RuntimeStringFormat.swift:709` の `__string_replaceIndent` と `RuntimeABISpec+String.swift:3051` の spec を削除する
- [ ] DEADCODE-RUNTIME-014: [E0] `RuntimeStringFormat.swift:714` の `__string_replaceIndentByMargin` と `RuntimeABISpec+String.swift:3060` の spec を削除する
- [ ] DEADCODE-RUNTIME-015: [E0] `RuntimeStringFormat.swift:724` の `__string_format` と `RuntimeABISpec+String.swift:3071` の spec を削除する（KSP-418 の子タスク）
- [ ] DEADCODE-RUNTIME-016: [E0] `RuntimeStringStdlib.swift:1044` の `__string_lowercase` を削除する。bundled source の同名記載はコメントのみ
- [ ] DEADCODE-RUNTIME-017: [E0] `RuntimeStringStdlib.swift:1049` の `__string_uppercase` を削除する
- [ ] DEADCODE-RUNTIME-018: [E0] `RuntimeStringStdlib.swift:1054` の `__string_lowercase_locale` を削除する。live bridge `__kk_lowercase_locale` とは別シンボル
- [ ] DEADCODE-RUNTIME-019: [E0] `RuntimeStringStdlib.swift:1059` の `__string_uppercase_locale` を削除する。live bridge `__kk_uppercase_locale` とは別シンボル

### Runtime / RuntimeABI: Swift helper・property・typealias

- [ ] DEADCODE-RUNTIME-020: [R0] `RuntimeCollectionHelpers.swift:676` の `runtimeInvokeCollectionLambda5(...)` を削除する
- [ ] DEADCODE-RUNTIME-021: [D: RUNTIME-020] `RuntimeCollectionHelpers.swift:601` の `RuntimeCollectionLambda5` typealias を削除する
- [ ] DEADCODE-RUNTIME-022: [R0] `RuntimeCoroutineContext.swift:569` の `dispatchQueue(for:)` を削除する。live dispatch は `runtimeResolveDispatcher(from:)` + `RuntimeDispatcher.queue`
- [ ] DEADCODE-RUNTIME-023: [R0] `RuntimeReflection.swift:26` の private `runtimeReflectionStringRaw(_:)` を削除する
- [ ] DEADCODE-RUNTIME-024: [R0] `RuntimeRandom.swift:46` の `SeededRandomBox.nextInt(bound:)` を削除する
- [ ] DEADCODE-RUNTIME-025: [R0] `RuntimeRandom.swift:53` の `SeededRandomBox.nextIntRange(from:until:)` を削除する
- [ ] DEADCODE-RUNTIME-026: [R0] `RuntimeRandom.swift:65` の `SeededRandomBox.nextDouble()` を削除する
- [ ] DEADCODE-RUNTIME-027: [R0] `RuntimeRandom.swift:72` の `SeededRandomBox.nextFloat()` を削除する
- [ ] DEADCODE-RUNTIME-028: [R0] `RuntimeRandom.swift:78` の `SeededRandomBox.nextBoolean()` を削除する。`SecureRandomBox` が使う `nextBits()` と test-only `nextFullInt()` は残す
- [ ] DEADCODE-RUNTIME-029: [W0/effectless] `RuntimeCoroutine.swift:914` の `RuntimeJobHandle.setParent(_:)` と製品 5 + test 2 の call site を削除する。唯一の効果は unread `parentJob` への代入で、子キャンセルは `registerChild` が担う
- [ ] DEADCODE-RUNTIME-030: [W0; 前提 RUNTIME-029] `RuntimeCoroutine.swift:865` の weak `RuntimeJobHandle.parentJob` を削除する
- [ ] DEADCODE-RUNTIME-031: [R0] `RuntimeCoroutine.swift:1239` の `RuntimeCoroutineScope.setParent(_:)` を削除する。live パスは `scope.parent = ...` の直接代入
- [ ] DEADCODE-RUNTIME-032: [R0] `RuntimeNativeAPI.swift:527` の `RuntimeCValuesBox.rawAddress` を削除する
- [ ] DEADCODE-RUNTIME-033: [R0] `RuntimePath.swift:1867` の `RuntimeFileVisitorBox.onVisitFileFailedRaw` を削除する。setter/reader/stub/test は全て 0
- [ ] DEADCODE-RUNTIME-034: [W0] `RuntimeTypes.swift:2102` の `RuntimeInputStreamBox.markOffset` と initializer 代入を削除する
- [ ] DEADCODE-RUNTIME-035: [W0] `RuntimeTypes.swift:2103` の `RuntimeInputStreamBox.markLimit` と initializer 代入を削除する。`mark` は明示的 no-op、`reset` は常に false
- [ ] DEADCODE-RUNTIME-036: [W0] `RuntimeMemory.swift:13` の `RuntimeMemorySnapshot.usedBytes` を削除する。同名 local は `totalBytes` 計算に必要なため残す
- [ ] DEADCODE-RUNTIME-037: [W0] `RuntimeMemory.swift:17` の `RuntimeMemorySnapshot.heapObjectCount` を削除し、snapshot 作成時の GC-lock/count 計算も消す
- [ ] DEADCODE-RUNTIME-038: [W0] `RuntimeMemory.swift:18` の `RuntimeMemorySnapshot.uptimeNanos` を削除し、`runtimeCaptureMemorySnapshot(nowNanos:)` の不要引数/default も整理する
- [ ] DEADCODE-RUNTIME-039: [R0/public property] `RuntimeABISpec+Char.swift:3` の `RuntimeABISpec.charClassificationFunctions` を削除し、空になるファイルも削除する。内包 25 spec は全て `charFunctions` 等に重複登録済みで `allFunctions`/C header は不変
- [ ] DEADCODE-RUNTIME-040: [R0] `RuntimeTypes.swift:2323` の `RuntimeOutputStreamBox.isClosed` を削除する。常に `false` を返す未参照 property
- [ ] DEADCODE-RUNTIME-041: [R0] `RuntimeCoroutine.swift:788` の `RuntimeTaskHandle.awaitResultThrowing(outThrown:)` を削除する。suspend-aware/live な `awaitResult` 経路は残す
- [ ] DEADCODE-RUNTIME-042: [R0 overload] `RuntimeStringFormat.swift:151` の private `runtimeFormatString(_:arguments: [Int], locale:)` を削除する。`[RuntimeValue]` overload は live
- [ ] DEADCODE-RUNTIME-043: [R0 requirement] `RuntimeRangeSharedHOF.swift:12` の `RuntimeRangeHOFKind.count(_:)` protocol requirement を削除する
- [ ] DEADCODE-RUNTIME-044: [D: RUNTIME-043] `RuntimeRangeSharedHOF.swift:42` の `RuntimeSignedRangeHOFKind.count(_:)` witness を削除する
- [ ] DEADCODE-RUNTIME-045: [D: RUNTIME-043] `RuntimeRangeSharedHOF.swift:95` の `RuntimeUnsignedRangeHOFKind.count(_:)` witness を削除する

### LSPServer

- [ ] DEADCODE-LSP-001: [W0] `Server.swift:17` の private `Server.log` closure property と initializer 内代入 `:26` を削除する
- [ ] DEADCODE-LSP-002: [D: LSP-001 / public API 確認] `Server.init(connection:analyzer:log:)` の未使用 `log` parameter を削除する。source compatibility 影響を release note または deprecated overload で処理する

### Tests: 未使用 helper / closure / enum case

> XCTest `test*`、Swift Testing `@Test` / `@Suite`、override / protocol witness は除外済み。以下は private/local の lexical scope または test module USR で caller 0 を確認したもののみ。

- [ ] DEADCODE-TEST-001: [R0] `LoweringPassRegressionTests.swift:504` の private `runLowering(module:interner:moduleName:emit:sema:diagnostics:)` を削除する
- [ ] DEADCODE-TEST-002: [R0] `ASTEquivalenceRegressionTests.swift:28` の private `isUserSourceRange(_:in:)` を削除する
- [ ] DEADCODE-TEST-003: [R0] `RuntimeCharArithmeticTests.swift:11` の private `runtimeString(_:)` を削除する
- [ ] DEADCODE-TEST-004: [R0] `RuntimeCharTests+EdgeCases.swift:20` の private `runtimeString(_:)` を削除する（TEST-003 とは別 USR）
- [ ] DEADCODE-TEST-005: [R0] `RuntimeStringArrayTests.swift:3775` の private `assertStringValueList(...)` を削除する
- [ ] DEADCODE-TEST-006: [R0] 同ファイル `:3859` の private `assertIndexedStringValue(...)` を削除する
- [ ] DEADCODE-TEST-007: [R0] 同ファイル `:3881` の private `assertIndexedCharValue(...)` を削除する
- [ ] DEADCODE-TEST-008: [R0] 同ファイル `:3903` の private `assertStringPairValue(...)` を削除する
- [ ] DEADCODE-TEST-009: [R0/local] `RuntimeTestsParallel/NumericBitCountTests.swift:171` の local `assertSingleBitSet(...)` を削除する
- [ ] DEADCODE-TEST-010: [R0] `RuntimeCollectionHOFTests.swift:60` の private `filterEvenIndex` C closure を削除する。`@convention(c)` だが export/unsafeBitCast/registration は 0
- [ ] DEADCODE-TEST-011: [R0] `RuntimeComparatorTests.swift:34` の private `primitiveComparatorDescendingTrampoline` C closure を削除する
- [ ] DEADCODE-TEST-012: [R0 case] `RuntimeFlowTests.swift:24` の private `RuntimeFlowTag.transform` case を削除する
- [ ] DEADCODE-TEST-013: [R0 case] `RuntimeFlowTests.swift:25` の `RuntimeFlowTag.takeWhile` case を削除する
- [ ] DEADCODE-TEST-014: [R0 case] `RuntimeFlowTests.swift:26` の `RuntimeFlowTag.dropWhile` case を削除する
- [ ] DEADCODE-TEST-015: [R0 case] `RuntimeFlowTests.swift:27` の `RuntimeFlowTag.buffer` case を削除する
- [ ] DEADCODE-TEST-016: [R0 case] `RuntimeFlowTests.swift:29` の `RuntimeFlowTag.flowOn` case を削除する。`RuntimeFlowTag(rawValue:)` の動的生成は 0
- [ ] DEADCODE-TEST-017: [R0] `RuntimeStringArrayTests.swift:380` の private `flatStringReturnValue(_:other:using:)` を削除する
- [ ] DEADCODE-TEST-018: [R0] 同ファイル `:413` の private `flatStringReturnValue(_:other:ignoreCase:using:)` を削除する
- [ ] DEADCODE-TEST-019: [D: TEST-017] 同ファイル `:76` の private `RuntimeFlatStringReturnWithStringEntry` typealias を削除する
- [ ] DEADCODE-TEST-020: [D: TEST-018] 同ファイル `:107` の private `RuntimeFlatStringReturnWithStringBoolEntry` typealias を削除する
- [ ] DEADCODE-TEST-021: [R0] `RuntimeTestIsolationSupport.swift:210` の `durationFromNanosecondsLong(_:)` を削除する
- [ ] DEADCODE-TEST-022: [R0] 同ファイル `:212` の `durationFromMillisecondsLong(_:)` を削除する
- [ ] DEADCODE-TEST-023: [R0] 同ファイル `:213` の `durationFromSecondsLong(_:)` を削除する
- [ ] DEADCODE-TEST-024: [R0] `BigIntegerSyntheticLinkTests.swift:8` の private `allExprIDs(in:where:)` を削除する
- [ ] DEADCODE-TEST-025: [R0] `VirtualDispatchTests.swift:152` の `makeItableFixture()` を削除する
- [ ] DEADCODE-TEST-026: [R0] `CompilerBackendTests/Integration/TestSupport/ASTHelpers.swift:5` の `topLevelFunction(named:in:interner:)` を削除する
- [ ] DEADCODE-TEST-027: [R0] `CompilerBackendTests/Integration/TestSupport/Assertions.swift:25` の `assertDiagnosticCount(...)` を削除する
- [ ] DEADCODE-TEST-028: [R0] `CompilerBackendTests/Integration/TestSupport/CompilationTestHelpers.swift:40` の `assertKotlinSourcesToKIR(...)` を削除する
- [ ] DEADCODE-TEST-029: [R0] `CompilerBackendTests/Integration/TestSupport/Filesystem.swift:5` の `makeRange(file:start:end:)` を削除する
- [ ] DEADCODE-TEST-030: [R0] 同ファイル `:12` の `makeToken(kind:file:start:end:leadingTrivia:trailingTrivia:)` を削除する
- [ ] DEADCODE-TEST-031: [R0] `CompilerBackendTests/Integration/TestSupport/KIRAndLLVM.swift:6` の `typeTokenSymbolOffset` 定数を削除する
- [ ] DEADCODE-TEST-032: [R0] 同ファイル `:9` の `coroutineDispatchLabelBase` 定数を削除する
- [ ] DEADCODE-TEST-033: [R0] 同ファイル `:62` の `firstExprID(in:where:)` を削除する
- [ ] DEADCODE-TEST-034: [R0] 同ファイル `:74` の `lastExprID(in:where:)` を削除する
- [ ] DEADCODE-TEST-035: [R0] `CompilerBackendTests/Integration/TestSupport/Pipeline.swift:78` の `makeContextFromSource(_:frontendFlags:)` を削除する
- [ ] DEADCODE-TEST-036: [R0] 同ファイル `:89` の `makeContextFromSources(_:)` を削除する
- [ ] DEADCODE-TEST-037: [R0] `CompilerBackendTests/Integration/TestSupport/SemaHelpers.swift:5` の `makeSema(source:)` を削除する
- [ ] DEADCODE-TEST-038: [R0] 同ファイル `:18` の `allExternalLinks(fqPath:sema:interner:)` を削除する
- [ ] DEADCODE-TEST-039: [R0] 同ファイル `:30` の `memberCallExprIDs(named:in:interner:)` を削除する
- [ ] DEADCODE-TEST-040: [R0] `CompilerCoreTests/Integration/TestSupport/CompilationTestHelpers.swift:80` の `assertKotlinCompilesToObject(...)` を削除する
- [ ] DEADCODE-TEST-041: [R0] `CompilerCoreTests/Integration/TestSupport/SemaHelpers.swift:17` の `allExternalLinks(fqPath:sema:interner:)` を削除する（TEST-038 とは別 test module USR）

---

## コード共通化タスク（REFACT: 2026-06-28 調査）

> 調査方法: KIR 層・Lowering 層・Sema 層・テスト層を横断して重複パターンを抽出。
> 優先度は影響ファイル数と「新 primitive 型追加時の修正箇所数」で決定。
> 完了ゲートは全テスト + golden + `diff_kotlinc.sh` green。

### HIGH: 影響大（多数ファイル or バグ温床）

- [ ] REFACT-003: synthetic 拡張関数の登録ボイラープレートを共通化する — symbol 定義 → パラメータループ → `setFunctionSignature` の一連の処理が `HeaderHelpers+SyntheticStringRegistrationHelpers.swift`・`+SyntheticSequenceRegistrationHelpers`・`+SyntheticMutableListStubs`・`+SyntheticMathStubs`・`+SyntheticPathStubs+SymbolRegistration` の 5 ファイルで 60〜90 行ずつ重複している。共有ファイルに `registerSyntheticFunctionStub(...)` フリー関数を定義して各ヘルパーから呼び出す
- [ ] REFACT-005: `resolveClassTypeSymbol` ヘルパーを共通化する — `guard case let .classType(...) = sema.types.kind(of: sema.types.makeNonNullable(...))` という 3 行ガードが 61 ファイルに散在している。`func resolveClassTypeSymbol(_ type: TypeID, sema: SemaModule) -> (ClassType, Symbol)?` のような共有ヘルパーを定義して置き換える

### MEDIUM: 局所的だが改善余地あり

- [ ] REFACT-009: boxing/unboxing call を emit する 3 行パターンを共通ヘルパーに抽出する — `appendExpr` + `instructions.append(.call(symbol: nil, canThrow: false, ...))` の組み合わせが `CallLowerer.swift`・`LambdaLowerer.swift`・`ABILoweringPass+BoxingRules.swift`・`CollectionLiteralLoweringPass+FactoryPredicates.swift` 等 12 箇所以上に重複している。`emitNonThrowingCall(callee:arg:resultType:arena:into:)` のようなヘルパーに集約する

### LOW: 軽微な冗長


## Stdlib Kotlin 化 実行計画（KSP）

> RF-STDLIB / M1–M17 / MIGRATION-* の**実行体**。設計: [`docs/stdlib-pipeline.md`](docs/stdlib-pipeline.md)。棚卸し日: 2026-07-01（シンボル名は当日時点の実コードで検証済み。行番号は書かない — アンカーは必ず rg で引く）。2026-07-10 ギャップ監査で KSP-CAP / KSP-INF / KSP-W6 / CLEANUP-STUB-096+ / バグバックログを追補。
> 依存: W0 → W1 → W2 は直列。W3 以降は「前提」欄に従い並列可。**言語機能ブロッカーは KSP-CAP-* として独立管理し、各タスクは必要 CAP を「前提」に宣言する（ブロッカー先行の原則）**。
> **粒度ルール**: 1タスク = 1 PR。目安「削除対象 kk_* ≤ 15・単一責務・golden 更新1回」。超えると判明したら枝番でなく新番号で分割する。
> クローズ記録: 旧 `STDLIB-JVM-166`（Java プレビュー機能）/ `STDLIB-REFL-175`（アノテーション処理高度機能）は 2026-07-07 #4582 で未完了のまま削除されたが、**ターゲット外として意図的クローズ**とする（2026-07-10 決定。復活させない）。
>
> **共通ゲート G**（全タスクの完了条件に含む）: `bash Scripts/swift_test.sh` / `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` すべて green。`Scripts/loc_report.sh` が存在する場合、`HeaderHelpers+Synthetic*` 行数・`"kk_` リテラル数の悪化なし。**完了マークは enforcing（テスト or rg チェック）の green 実績を完了メモに書けるものに限る — ドキュメント同期や部分検証のみでの完了は禁止**。TODO.md 編集時のゲート: **タスク定義行の ID 重複ゼロ**（`rg -o '^- \[.\] [A-Z][A-Z0-9-]*-[0-9]+' TODO.md | sort | uniq -d` が空）。※`Scripts/check_todo_ids.sh` は本文中のクロスリファレンス（`前提: KSP-CAP-004` 等）も重複計上する仕様のため 3 セグメント ID の相互参照で赤くなる — 定義行限定の検出への改修は KSP-INF-014。
> **golden 更新 U**: `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` → `git diff -- Tests/CompilerCoreTests/GoldenCases` が機械的差分のみであること。
> **移行テンプレート T**（W2〜W4/W6 の各タスクはこの手順）:
> 1. タスク記載の diff ケースを `Scripts/diff_cases/` で確認・なければ追加し、**現行実装**で `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` green を確認（挙動の固定）
> 2. タスク記載の実装先 .kt に Kotlin 実装を書く（既存ファイル追記可）。ランタイム依存点は `@KsSymbolName("__kk_...") internal external fun __名前(...)` で宣言
> 3. 新規 .kt は `Sources/CompilerCore/Stdlib/kotlin/` 配下に置くだけで自動配線される。除外リスト対象は `Sources/CompilerCore/Driver/FrontendPhases.swift` の `excludedBundledStdlibFiles` から該当エントリを削除
> 4. **同一 PR** で、タスク記載の (a) `HeaderHelpers+Synthetic*` の該当登録 (b) `CallTypeChecker+*` / `CallLowerer+*` の名前文字列特例 case (c) Runtime の `@_cdecl` 関数 (d) `RuntimeABISpec` の該当エントリ（parity テスト含む）を削除する。「ブリッジ残留」指定の関数は削除せず `__kk_` prefix へ改名し spec を更新
> 5. U → G → タスク記載の rg 完了チェックが 0 件
> 6. **移行完了の3点確認**: ①除外リスト非登録 ②.kt 本体が実ロジック（`= this` 等のフェイク禁止 — 実例: RangeCoercion.kt） ③Sema/KIR/Lowering に同名 name-string 特例が残っていない
> 7. **二重 oracle**: diff ケースに加え、bundled .kt を実行して期待値比較する自己完結テスト（KSP-INF-006 のハーネス整備後は必須。整備前は G の既存テストで代替可）
> 8. ブリッジ（`__kk_*`）を**追加**する場合は理由コード（syscall / メモリ表現 / GC・continuation / メタデータ / 性能=実測値添付）を PR 本文に明記し、`RuntimeABISpec` 登録 + specVersion 更新をセットで行う。本家 kotlin-stdlib から移植した .kt には Apache 2.0 帰属ヘッダを付ける（KSP-INF-013）

### KSP-W0: 基盤（RF-STDLIB-003/006/007 の細分化。直列で実施）

- [x] KSP-001: bundled 宣言インデックスを構築する
  - 前提: なし
  - 変更: 新規 `Sources/CompilerCore/Sema/DataFlow/BundledDeclarationIndex.swift` / `Sources/CompilerCore/Sema/DataFlow/Phase.swift` / `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers.swift` の `registerSyntheticDelegateStubs(symbols:types:interner:)`
  - 手順: (0) `Phase.swift` の `run()` では synthetic 型基盤が先に必要なため、bundled ソース宣言の SymbolTable 登録は `registerSyntheticDelegateStubs` より後に残す (1) パスが `__bundled_` で始まる fileID 集合を `ctx.sourceManager` から取り、AST から bundled 関数/プロパティ/nominal member の `(所有型FQName, メンバ名, パラメータ数)` Set を持つ struct `BundledDeclarationIndex` を実装する。post-header 利用向けの SymbolTable builder は同じ key 規則で保持する (2) `registerSyntheticDelegateStubs` に引数 `bundledIndex`（既定 `.empty`）を追加し `Phase.swift` から渡す
  - 検証: `swift build` + G（このタスクでは挙動不変）
  - 完了: `BundledDeclarationIndex` を追加し、`Phase.swift` から `registerSyntheticDelegateStubs(... bundledIndex:)` へ渡す。
- [x] KSP-002: 優先規則（Kotlin ソース > 合成スタブ）を実装する
  - 前提: KSP-001
  - 変更: `HeaderHelpers.swift` と各 `HeaderHelpers+Synthetic*` が使う共通登録ヘルパ
  - 手順: (1) `rg -n 'func register' Sources/CompilerCore/Sema/DataFlow/HeaderHelpers.swift` で、メンバ/トップレベル関数シンボルを SymbolTable へ insert する共通ヘルパを特定 (2) insert 直前に `bundledIndex` に同 `(owner, name, arity)` があれば登録をスキップ (3) スキップ件数を debug ログ可能にする
  - 検証: G + U（bundled 由来 API のスタブが消えるため Sema golden 差分が出る — 機械的差分であることを確認）
  - 完了: `BundledKotlinStdlib.kotlinCollectionsSource` の `count`/`any`/`all` に対応する合成スタブが登録されないことをテストで assert
- [x] KSP-002-FOLLOWUP: `HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift` の List indexed メンバー (`withIndex`, `forEachIndexed`, `mapIndexedNotNull`, `foldIndexed`, `reduceIndexed`, `reduceIndexedOrNull`, `runningFoldIndexed`, `runningReduceIndexed`, `scanIndexed`, `foldRightIndexed`, `reduceRight`) と ArrayDeque メンバー登録に `BundledSyntheticStubRegistration.shouldSkipRegistration` 経由の skip guard を追加。症状: bundled .kt で同名 API を追加すると `symbols.define(kind: .function)` が先行して合成シンボルを作成し、collectAllHeaders 後に `KSWIFTK-SEMA-0102` warning が出る。再現: 該当 bundled .kt に `List<T>.forEachIndexed(action: (Int, T) -> Unit)` 等を追加し `BundledSyntheticOverlapDiagnosticTests` を実行。発見元タスク ID: KSP-002 / RF-STDLIB-003。
- [x] KSP-003: 二重定義 warning 診断を追加する
  - 前提: KSP-002
  - 変更: `Sources/CompilerCore/Driver/DiagnosticRegistry.swift` の `semaDescriptors` / `Phase.swift`
  - 手順: (1) `rg 'KSWIFTK-SEMA-' Sources/CompilerCore/Driver/DiagnosticRegistry.swift` で未使用番号を採番し descriptor 追加 (2) `registerSyntheticDelegateStubs` 完了後、bundled インデックスと `.synthetic` フラグ付きシンボルの `(owner, name, arity)` 交差を検出したら `ctx.diagnostics.warning(...)`（= KSP-002 のガード漏れ検知） (3) 診断テスト追加
  - 検証: G
  - 完了: `KSWIFTK-SEMA-0102` を登録し、synthetic/bundled overlap の warning 診断テストを追加。
- [x] KSP-004: bundled ソースの fileID 順序不変条件テストを追加する
  - 前提: なし（並列可）
  - 変更: 新規 `Tests/CompilerCoreTests/Driver/BundledStdlibOrderingTests.swift`
  - 手順: `LoadSourcesPhase` 実行後の `sourceManager.fileIDs()` について (a) `__bundled_*` がユーザー入力より前 (b) `__bundled_*` 同士が相対パス辞書順、を assert
  - 検証: G
- [x] KSP-005: golden Sema ダンプから bundled 由来シンボルを除外する
  - 前提: KSP-004
  - 変更: `Sources/GoldenHarnessSupport/GoldenHarnessDump.swift` の `dumpSema(sourcePath:)`
  - 手順: `Sources/CompilerCore/Sema/Models/MetadataSerializer.swift` の `buildRecords` にある excludedFileIDs（`__bundled_*` の declSite 除外）と同じフィルタを dumpSema に適用 → U で一括更新
  - 完了: `rg '__bundled_' Tests/CompilerCoreTests/GoldenCases` が 0 件 + G
- [x] KSP-006: bundled stdlib のコンパイル時間を PhaseTimer で分離計測する
  - 前提: なし（並列可）
  - 変更: `Sources/CompilerCore/Driver/FrontendPhases.swift`（Lex/Parse ループ）。`PhaseTimer.swift` は変更不要（`recordSubPhase(_:startTime:endTime:)` を利用）
  - 手順: Lex/Parse（および可能なら Sema）で `__bundled_` プレフィックス fileID の処理時間を集計し、各フェーズに `recordSubPhase("bundled-stdlib", ...)` を記録
  - 検証: G + タイミング出力に bundled-stdlib 行が出ること
- [x] KSP-007: bundled 注入コストのベースラインを記録する
  - 前提: KSP-006
  - 変更: `docs/refactoring-metrics.md`
  - 手順: (1) `rg -n 'phaseRecords' Sources` で PhaseTimer 出力の表示経路を確認 (2) `.build/debug/kswiftc Scripts/diff_cases/hello.kt -o /tmp/ksp_out` で計測 3 回の中央値を取得 (3) 「bundled stdlib 注入コスト」節を追記し、キャッシュ着手トリガー閾値（+100ms）を正式化
- [x] KSP-008: 設計文書の opt-out フラグ名を実装に合わせる
  - 前提: なし（並列可）
  - 変更: `docs/stdlib-pipeline.md` §4
  - 手順: opt-out フラグ名を実名 `--no-stdlib`（`Sources/KSwiftKCLI/CLIParser.swift` / `CompilerOptions.includeStdlib`）で記述する
  - 完了: `docs/stdlib-pipeline.md` §4 を `Sources/KSwiftKCLI/CLIParser.swift` の `--no-stdlib` / `CompilerOptions.includeStdlib` 表記に同期。

### KSP-W1: @KsSymbolName ブリッジ機構（W0 完了後、直列）


### KSP-W2: 縦切りテンプレート（1 タスク = 1 PR。以後の移行の見本）


### KSP-CAP: コンパイラ言語機能ブロッカー（2026-07-10 実機プローブで全件実測。移行タスクより先行して解消する）

> stdlib を本家形の Kotlin で書くために必要な言語機能の台帳。再現 .kt は各タスク着手時に `Scripts/diff_cases/` or 回帰テストへ固定する（プローブ時の最小再現はセッション記録 probes/p01〜p12b にあり、診断コードから容易に再構成可能）。完了条件は共通で「再現ケースが期待動作でコンパイル・実行され、回帰テストとして固定される + G」。

- [ ] KSP-CAP-001: object 式のメンバ関数本体から外側ローカル変数をキャプチャできるようにする（現状 `KSWIFTK-SEMA-0022` Unresolved reference。プロパティ初期化子でのキャプチャは動作済み）。ブロック対象: KSP-441 全体・KSP-631・KSP-651 の sequence{}
- [ ] KSP-CAP-002: for-in がユーザー実装 Iterator/Iterable で1回も回らず黙って終了する lowering 欠陥を修正する（= BUG-013。`hasNext()`/`next()` 手動呼び出しは動作する）。ブロック対象: KSP-441 以降の全 Sequence/Iterator 系
- [ ] KSP-CAP-003: companion object をレシーバとする拡張関数の呼び出しを解決する（`fun Foo.Companion.make()` → `Foo.make()` が `KSWIFTK-SEMA-0024`。宣言自体は通る。ネストクラスレシーバは動作済み）。ブロック対象: KSP-472 の `kk_instant_now`/`kk_clock_system_now` 配線
- [ ] KSP-CAP-004: `while(true)` CAS ループ / `Nothing` 戻り値無限ループの型検査を通す（`KSWIFTK-TYPE-0001`。該当する制御フロー解析は未実装であることをコード確認済み）。ブロック対象: KSP-673・`AtomicMigration.kt` コメントの保留解除
- [ ] KSP-CAP-005: 合成登録された組込み `Comparator` の SAM コンストラクタを解決する（`KSWIFTK-SEMA-0023`。ユーザー宣言 `fun interface` の SAM 変換は健全 — `.funInterface` フラグ付き合成シンボルのみ解決対象外）。ブロック対象: KSP-309/461
- [ ] KSP-CAP-006: クラスと同名のトップレベル関数の共存を許可する（シグネチャが異なっても `KSWIFTK-SEMA-0001` Duplicate declaration）。ブロック対象: 本家構造準拠全般（KSP-466 の Random で構造回避を強いた実績 = 逸脱台帳の主要解消条件）
- [ ] KSP-CAP-007: プリミティブ型を返す operator getValue/setValue delegate の unboxing を修正する（= BUG-014。`val x by Prop()` が Int でなく生ポインタを返す。参照型は正常）。ブロック対象: KSP-491/492 完全化・KSP-680
- [ ] KSP-CAP-008: ジェネリックレシーバの関数リテラル `T.() -> Unit` を通す（`KSWIFTK-SEMA-0014` "Val cannot be reassigned" を誤検出。具象型レシーバは動作済み）。ブロック対象: KSP-602・KSP-622〜624
- [ ] KSP-CAP-009: supertype 位置の関数型リテラルをパースする（`class KProperty0<V> : () -> V` 相当。`BuildASTPhase+MemberCollection.swift` の supertype パーサ制約）。ブロック対象: KSP-682
- [ ] KSP-CAP-010: `CoroutineLoweringPass+Flow.swift` の provenance+名前一致による無条件 `kk_flow_*` 書き換えを「合成スタブ由来と確認できる場合のみ」に限定する（`FlowLoweringNames`。着手前にダミー実装差し替えテストで検証 — `docs/stdlib-pipeline.md` §9 の手順）。ブロック対象: KSP-499・KSP-674〜676
- [ ] KSP-CAP-011: vtable スロットが同アリティ兄弟オーバーロードで衝突する問題を修正する（= BUG-011。PR #4707 open が該当）。ブロック対象: KSP-466 残課題（shuffled(random) 等の決定性回復）・BUG-005
- [ ] KSP-CAP-013: ジェネリック関数の期待型制約を解決する（症状: `val x: Lazy<Int> = lazyOf(1)` と `val x: Lazy<Int> = lazy { 1 }` が `KSWIFTK-TYPE-0001`。最小再現: `Scripts/diff_cases/generic_function_expected_type.kt`。発見元: BUG-017/KSP-681）。ブロック対象: KSP-681。真因は `lazyOf`/`lazy` 自体の戻り値型登録（元々 `kotlin.Lazy` で正しい）ではなく、`Sources/CompilerCore/Sema/TypeCheck/Helpers.swift` の `resolveTypeRef` が単一セグメントの型参照解決でスコープ（import優先順位）を無視し、`lookupByShortName` による全パッケージ横断のショートネーム走査（生シンボルID昇順の先頭を採用）へフォールバックしていたこと。デフォルトimport対象外の `kotlin.properties.Lazy`（0引数のマーカーinterface）が `kotlin.Lazy`（`lazyOf`/`lazy` が返す `out T` interface）より先に登録されているため、ユーザーコードの `Lazy<Int>` という型注釈が誤ってそちらに解決されていた。修正: `resolveTypeRef` で単一セグメント型参照をまずスコープから解決するよう変更。同一調査で副次的に発見した2件も同PRで修正: (1) `lazy(mode) { }` の2引数オーバーロードが `lazyModeSymbol` の旧fqName（`kotlin.lazy.mode`）により `ScopeBuilder.collectLibraryTopLevelSymbolsByPackage` のパッケージ推定で実在しない `kotlin.lazy` に分類され、デフォルトimportスコープから到達不能で `KSWIFTK-SEMA-0002` になっていた（＝BUG-017が指していた症状の実体。fqNameを `kotlin.lazy$mode` に変更して解消）。(2) ラムダの期待戻り型が未制約の型パラメータのとき型パラメータ自体を漏らして返していたため `lazy { 1 }` のT推論が自己参照制約になり失敗していた（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）。(3) `RuntimeLazyBox.evaluateInitializer()` が初期化子を常に生thunkポインタとして直接bitcastしており、プレーンな `lazy { }` 呼び出し（クロージャ変換経路のboxed Function0）で実行時クラッシュしていたため `kk_function_invoke_0` 経由の呼び出しに修正（`Sources/Runtime/RuntimeTypes.swift`）。検証: `Tests/CompilerCoreTests/Sema/GenericFunctionExpectedTypeConstraintTests.swift`、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+PropertyDelegateEdgeCases.swift`（`testCodegenCompilesLazyBlockValueRead`/`testCodegenCompilesLazyBlockCapturingOuterVariable`）、`Scripts/diff_cases/generic_function_expected_type.kt`（`diff_kotlinc.sh` PASS）。フルゲートはホストの同時実行負荷（8コアでload average 280超。原因はホスト上の並行セッション、後にホスト再起動で解消）により手元では完走確認できず、CI（`Verification 5/5 kotlinc Diff` 全3シャード・`Verification 2-4/5 Backend/Runtime/CLI/LSP`）で確認。CIで唯一検出された `Golden.Sema`（`string_zip.kt`）の差分は、本修正のラムダ戻り値型推論改善（未解決の型パラメータ `kotlin.text.zip.R` ではなく具体化された `String` を報告するようになった）の正当な帰結と確認し、golden を更新済み。修正PR: #4976（マージ後に`[x]`化する）
- [ ] KSP-CAP-012: bundled ソース内 suspend fun のコンパイル対応を検証する（ユーザーソースでは動作実測済み・bundled 内使用実績 0 件のため未検証）。ブロック対象: KSP-499・KSP-674〜679

### KSP-INF: パイプラインのインフラ・検証（2026-07-10 監査で判明した設計要求の未実装分）

- [ ] KSP-INF-001: `--no-stdlib` を実装する（**現状デッドフラグ**: `CLIParser.swift` でパースするが `CompilerOptions.includeStdlib` の読み出し箇所ゼロ、`LoadSourcesPhase.run` は無条件注入）。`FrontendPhases.swift` で分岐 + CLI テスト + 動作テスト追加。完了: includeStdlib の読出実装 + テスト green + G
- [ ] KSP-INF-002: bundled stdlib のフィンガープリントを `IncrementalCompilationCache` に含める（現状 `computeCurrentFingerprints` はユーザー入力のみ = bundled .kt 変更後も stale cache を再利用する正当性バグ）。`IncrementalBuildConfiguration` へ stdlib manifest hash を追加し、変更時は full rebuild に倒す
- [ ] KSP-INF-003: @KsSymbolName ↔ RuntimeABISpec の**型署名**突合を enforcing にする（KSP-103 はアリティのみ検証で完了扱いになっていた。`docs/stdlib-pipeline.md` §6 の「型署名が一致する」要求を充足する後継タスク）
- [ ] KSP-INF-004: `DiagnosticEngine` に severity 別集計（`hasWarning` 等）を追加し、「bundled stdlib 全体で診断ゼロ（warning 含む）」を横断 enforcing テスト化する（§8 の未実装要求）
- [ ] KSP-INF-005: Sema golden の `file f<N>` 行を fileID 生値から安定キーへ置換し、bundled .kt 追加時の golden 差分をゼロにする（`GoldenHarnessDump.swift` の renderFile。symbol/expr は StableRenderContext で安定済み）。不変条件テスト「ダミー bundled 1件注入で golden ダンプがバイト同一」を追加。U 一括更新はこれを最後にする。完了: `rg 'fileID\.rawValue' Sources/GoldenHarnessSupport` 0件 + テスト green + G
- [ ] KSP-INF-006: bundled .kt の自己完結実行テストハーネスを作る（.kt をコンパイル・実行し期待 stdout と比較。kotlinc 不要の第二 oracle。整備後、テンプレート T の手順7を必須化）
- [ ] KSP-INF-007: 移行 API の実行時性能ベンチ基盤を作る（現状ゼロ。「性能理由の Swift 残留はベンチ数値必須」運用の前提。まず filter/map/sort 等 HOF と for-in range のマイクロベンチ + 基準値を `docs/refactoring-metrics.md` に記録）
- [ ] KSP-INF-008: `SourceManager` に origin（user / bundledStdlib / residualStdlib）を持たせ、`__bundled_` prefix 文字列判定の重複 8 箇所（FrontendPhases / HeaderHelpers / BundledDeclarationIndex / KIRLoweringDriver+ModuleLowering(+FunDecl) / CodegenPhase ×2 / GoldenHarnessDump）を一元化する（`docs/stdlib-pipeline.md` §12 統合待ち事項）
- [ ] KSP-INF-009: bundled リソース欠落のサイレント縮退を診断化する（`injectBundledStdlib` が resourcePath 不在時に無言 return → `KSWIFTK-SOURCE-0101`（リソース不在）/`KSWIFTK-SOURCE-0102`（読込失敗）を採番して error 化。§12 統合待ち事項）
- [ ] KSP-INF-010: `RuntimeABISpec.specVersion` 更新の機械検証を追加する（`allFunctions` 内容ハッシュとの突合テスト。現状 "J35" 手動文字列で更新漏れを検出できない）
- [ ] KSP-INF-011: 宣言優先規則（KSP-002）のガード適用漏れを総点検する（実例: List/Array/Iterable/Sequence の joinTo 系登録が bundled `StringSplitJoin.kt` と二重定義のまま `KSWIFTK-SEMA-0102` も発火していない = `shouldSkipRegistration` 未経由の登録ヘルパーが存在）。全 register 系ヘルパーがガードを通ることの enforcing 化 + §12 の二重定義4象限（user vs bundled 等）の方針決定
- [ ] KSP-INF-012: bundled 注入コストの再計測を運用化する（W6 各モジュール完了時に `docs/refactoring-metrics.md` の +100ms トリガーを再判定。RF-GOV-004 の四半期監査に統合）
- [ ] KSP-INF-013: 本家移植のライセンス表記を整備する（kotlin-stdlib からの移植ファイルへ Apache 2.0 帰属ヘッダ + リポジトリ NOTICE を追加する規約を `docs/stdlib-pipeline.md` §6 に明文化し、既存移植分（`random/Random.kt` の XorWow 等）へ遡及適用）
- [ ] KSP-INF-014: `Scripts/check_todo_ids.sh` をタスク定義行（`- [ ] ID:` / `- [x] ID:`）限定の重複検出に改修する（現状は本文中のクロスリファレンスも重複計上し、KSP-CAP 参照の増加で常時赤 — 改修後に CI ゲート化を検討）

### KSP-W3: excludedBundledStdlibFiles 解消（前提: KSP-202。相互独立・並列可）

- [ ] KSP-301: ゴーストエントリ 5 件を削除する
  - 手順: `FrontendPhases.swift` の `excludedBundledStdlibFiles` から、実ファイルが存在しない `kotlin/ResultExtensions`, `kotlin/logging/AdvancedLogger`, `kotlin/reflect/KClassAnnotationRegistration`, `kotlin/text/StringBasics`, `kotlin/text/StringEncoding` を削除（`find Sources/CompilerCore/Stdlib -name '*.kt'` で不在を確認してから）
  - 注記(2026-07-10 監査): さらに `kotlin/comparisons/Comparators`, `kotlin/ranges/RangeIterators`, `kotlin/ranges/RangeMembership` の3件は対象ファイル未移設のため**現状 no-op の予約枠**（KSP-309/312 の移設時に初めて機能する）。削除せず予約枠である旨のコメントを付ける
  - 検証: G のみ
- [ ] KSP-302: StringIndentFormat を配線する（`trimIndent`/`trimMargin`/`prependIndent`/`replaceIndent`/`replaceIndentByMargin`）
  - 注意: **同一 PR で** `BundledKotlinStdlib.kotlinTextSource` 内の同名 5 関数を削除（二重定義になるため）。runtime `__string_trimIndent` 系 / `kk_string_trimIndent` 系（`RuntimeStringFormat.swift`）は Kotlin 版が完全なら削除、不足なら `__kk_` 降格
  - 手順: T / diff: `string_indent.kt`（既存）
- [ ] KSP-305: CollectionFactories を配線する（`listOf`/`setOf`/`mapOf`/`empty*`/`mutable*Of`）
  - 注意: `CollectionLiteralLoweringPass` がファクトリ呼び出しを直接 `kk_*` へ書き換えている。ブリッジ残留: 生成コア `kk_list_of`, `kk_set_of`, `kk_map_of`, `kk_emptyList`, `kk_emptySet`, `kk_emptyMap` は `__kk_` 降格（アロケーション主体のため）
  - 削除: `CallLowerer+StdlibArrayConstructor.swift` のファクトリ特例 / 各 `HeaderHelpers+Synthetic{List,Set,Map,Array}Stubs.swift` のファクトリ登録
  - 手順: T / diff: `collection_builders.kt`（既存）
  - CI 回帰（KSP-311 / PR #4572 で発見・修正）: source-backed collection factory の lowering 呼び出しが抜けると、`listOf(3, 2, 1)` が `kk_list_of(3, 1, 2)` のように array/count ABI へ誤渡しされ、結果が空リストになる。最小再現: `Scripts/diff_cases/compare_by.kt`（同時に `firstOrNull_simple.kt` など 12 ケースで発生）。`tryLowerCollectionFactoryCall` の呼び出しを復元
- [ ] KSP-308: SequenceWindowChunk を配線する（`take`, `takeWhile`, `drop`, `dropWhile`, `chunked`, `windowed`, `zip`, `zipWithNext`, `distinct`, `distinctBy`）
  - 前提: KSP-441（Sequence 遅延パイプラインの Kotlin 表現）。それまで着手不可
  - 削除: `kk_sequence_take`, `kk_sequence_takeWhile`, `kk_sequence_drop`, `kk_sequence_dropWhile`, `kk_sequence_chunked`, `kk_sequence_chunked_transform`, `kk_sequence_windowed`, `kk_sequence_windowed_transform`, `kk_sequence_zip`, `kk_sequence_zipWithNext`, `kk_sequence_zipWithNextTransform`, `kk_sequence_distinct`, `kk_sequence_distinctBy`（`RuntimeSequence.swift`）/ `HeaderHelpers+SyntheticSequenceTerminalStubs.swift` の同登録
- [x] KSP-309: Comparators を配線する（死蔵 `Stdlib/kotlin/comparisons/Comparators.kt` を `Sources/CompilerCore/Stdlib/kotlin/comparisons/` へ移設して配線）
  - 対象: `compareBy`×2, `compareByDescending`×2, `naturalOrder`, `reverseOrder`, `reversed`, `thenBy`, `thenByDescending`, `thenComparing`
  - 削除: `RuntimeComparator.swift` の対応 `kk_comparator_*`（trampoline 含む）/ `HeaderHelpers+SyntheticComparatorStubs.swift` の同登録 / `CallLowerer+StdlibComparisons.swift` の同 case
  - 注意: Comparator SAM ディスパッチ対応が前提（未対応ならブロッカーとして報告）/ diff: `comparisons_edge_cases.kt`（既存）
- [ ] KSP-311: StringBuilder を配線する（クラス + `append`系/`insert`/`delete`系/`reverse`/`toString` 等 34 関数）
  - 注意: コンストラクタは `CallSupportLowerer` 経由。可変内部バッファは `__kk_` ブリッジ最小集合（new/append_obj/toString/length など）に絞り、型別 append/insert/delete 系を Kotlin 化
  - 削除対象の確認: `rg -n 'kk_string_builder_' Sources/Runtime/RuntimeStringBuilder.swift Sources/CompilerCore` で全列挙 → 残留/削除を分類してから着手
  - 手順: T / diff: `ls Scripts/diff_cases | rg -i 'builder'` で確認・不足追加
- [ ] KSP-312: RangeIterators / RangeMembership を配線する（`iterator`/`contains`/`isEmpty` 各 Range/Progression）
  - 注意: `for (x in range)` は `ExprLowerer+ControlFlowAndBlocks.swift` が `.iterator()` を経由せず `kk_range_iterator`/`hasNext`/`next` へ直接特例化している（3 並列ディスパッチ）。本タスクは (1) 死蔵 2 ファイルの移設・配線 (2) `CallTypeChecker+RangeMemberFallback.swift` の該当特例削除まで。for-in 特例の撤去は KSP-452 で実施
  - 手順: T / diff: `range_basic.kt`, `range_contains.kt`（既存）

### KSP-W4: モジュール量産移行（各タスク = 1 PR。手順はすべて T）

#### kotlin.text [M1/M2 実行体]（前提: KSP-202。実装先は原則 `Sources/CompilerCore/Stdlib/kotlin/text/` の既存ファイルへ追記、なければ本家準拠名で新規）

- [ ] KSP-401: empty/blank/lines 系を Kotlin 化（`isEmpty`, `isNotEmpty`, `isBlank`, `isNotBlank`, `isNullOrEmpty`, `isNullOrBlank`, `ifEmpty`, `ifBlank`, `orEmpty`, `lines`, `lineSequence`）
  - 削除 kk_*: `kk_string_isEmpty`, `kk_string_isNotEmpty`, `kk_string_isBlank`, `kk_string_isNotBlank`, `kk_string_ifBlank`, `kk_string_ifEmpty`, `kk_string_orEmpty`, `kk_string_isNullOrEmpty`, `kk_string_isNullOrBlank`, `kk_string_lines`, `kk_string_lineSequence`（`RuntimeStringQuery.swift`）
  - 完了: `rg '"kk_string_is|"kk_string_if|"kk_string_orEmpty|"kk_string_lines' Sources/CompilerCore` 0 件 + G
  - 追記（2026-07-13, PR #4578 / 発見元 KSP-401）: `Scripts/diff_cases/string_linesequence.kt` の `こんにちは\n世界\n` で、source-backed `String.replace` が `StringIndexOutOfBoundsException` 相当の未処理例外を起こし candidate が exit 1 になった。flat String の UTF-8 byte length と文字単位の走査長が不一致だったためで、`StringSearchReplace.kt` の走査を `toList()` ベースへ修正済み（マージ後に本項を `[x]` 化する）。
- [ ] KSP-404: prefix/suffix 系を Kotlin 化（`startsWith`, `endsWith`, `removePrefix`, `removeSuffix`, `removeSurrounding`）
  - 削除 kk_*: `kk_string_startsWith`, `kk_string_endsWith`, `kk_string_removePrefix`, `kk_string_removeSuffix`, `kk_string_removeSurrounding`, `kk_string_removeSurrounding_pair`
- [ ] KSP-405: take/drop 系を Kotlin 化（`take`, `takeLast`, `drop`, `dropLast`, `takeWhile`, `dropWhile`, `takeLastWhile`）
  - 削除 kk_*: `kk_string_take`, `kk_string_takeLast`, `kk_string_drop`, `kk_string_dropLast`, `kk_string_takeWhile`, `kk_string_dropWhile`, `kk_string_takeLastWhile`
- [ ] KSP-406: substring/slice/range 編集系を Kotlin 化（`substring`, `subSequence`, `slice`, `removeRange`, `replaceRange`）
  - 削除 kk_*: `kk_string_substring`, `kk_string_subSequence`, `kk_string_slice_range`, `kk_string_slice_iterable`, `kk_string_removeRange`, `kk_string_removeRange_range`, `kk_string_replaceRange`, `kk_string_replaceRange_indices`（`RuntimeStringStdlib.swift`/`RuntimeStringSubstring.swift`）。基点の `substring(startIndex, endIndex)` のみ `__kk_` 降格可
- [ ] KSP-407: substringBefore/After・replaceBefore/After 系を Kotlin 化（各 String/Char 版）
  - 削除 kk_*: `kk_string_substringBefore(_char)`, `kk_string_substringAfter(_char)`, `kk_string_substringBeforeLast(_char)`, `kk_string_substringAfterLast(_char)`, `kk_string_replaceAfter(_char)`, `kk_string_replaceAfterLast(_char)`, `kk_string_replaceBefore(_char)`, `kk_string_replaceBeforeLast(_char)`（`RuntimeStringSubstring.swift`、計 16）
- [ ] KSP-408: contains/indexOf 系を Kotlin 化（`contains`, `indexOf`, `lastIndexOf`, `indexOfAny`, `lastIndexOfAny`, `findAnyOf`, `findLastAnyOf`, `indexOfFirst`, `indexOfLast` + ignoreCase/from 版）
  - 削除 kk_*: `kk_string_contains_str`, `kk_string_contains_ignoreCase`, `kk_string_indexOf`, `kk_string_indexOf_from`, `kk_string_indexOf_char`, `kk_string_indexOf_ignoreCase`, `kk_string_lastIndexOf`, `kk_string_lastIndexOf_char`, `kk_string_lastIndexOf_ignoreCase`, `kk_string_indexOfAny_chars`, `kk_string_indexOfAny_strings`, `kk_string_lastIndexOfAny_chars`, `kk_string_lastIndexOfAny_strings`, `kk_string_findAnyOf`, `kk_string_findLastAnyOf`, `kk_string_indexOfFirst`, `kk_string_indexOfLast`（`RuntimeStringStdlib.swift`/`RuntimeStringSearch.swift`）
- [ ] KSP-409: コレクション変換・iterator 系を Kotlin 化（`toList`, `toMutableList`, `toCharArray`, `toTypedArray`, `toCollection`, `toSortedSet`, `iterator`, `asIterable`, `asSequence`, `withIndex`）
  - 削除 kk_*: `kk_string_toList`, `kk_string_toMutableList`, `kk_string_toCharArray`, `kk_string_toTypedArray`, `kk_string_toCollection`, `kk_string_toSortedSet`, `kk_string_iterator`, `kk_string_iterator_hasNext`, `kk_string_iterator_next`, `kk_string_asIterable`, `kk_string_iterable_toList`, `kk_string_iterable_iterator`, `kk_string_asSequence`, `kk_string_withIndex`
- [ ] KSP-410: String HOF を Kotlin 化 [MIGRATION-TEXT-008]（`filter(Not/Indexed)`, `map(Indexed/NotNull)`, `any`, `all`, `none`, `count`, `fold`系, `reduce`系, `find(Last)`, `onEach(Indexed)`, `partition`, `sumBy(Double)`, `firstNotNullOf(OrNull)`）
  - 削除 kk_*: `RuntimeStringHOF.swift` の該当約 27 関数（`rg -o '@_cdecl\("kk_string_[a-zA-Z]+"\)' Sources/Runtime/RuntimeStringHOF.swift` で着手時に全列挙して固定）
- [ ] KSP-411: chunked/windowed/zip 系を Kotlin 化
  - 削除 kk_*: `kk_string_chunked`, `kk_string_chunked_sequence`, `kk_string_chunked_sequence_transform`, `kk_string_windowed_default`, `kk_string_windowed`, `kk_string_windowed_partial`, `kk_string_windowedSequence_partial`, `kk_string_windowedSequence_transform`, `kk_string_zip`, `kk_string_zipTransform`, `kk_string_zipWithNext`, `kk_string_zipWithNextTransform`
- [ ] KSP-412: case 変換を完遂する（`capitalize`, `replaceFirstChar` を Kotlin 化、locale 版は `__kk_` 降格）
  - 既存 `StringCaseConversion.kt` が `__kk_lowercase_locale`/`__kk_uppercase_locale` 委譲パターンの見本
  - 削除 kk_*: `kk_string_capitalize`, `kk_string_replaceFirstChar` / 降格: `kk_string_lowercase_locale`, `kk_string_uppercase_locale`
- [ ] KSP-413: 比較系を Kotlin 化（`compareToIgnoreCase`, `contentEquals`, `equals(ignoreCase)`）
  - 削除 kk_*: `kk_string_compareToIgnoreCase`, `kk_string_contentEquals`, `kk_string_contentEquals_ignoreCase` / 降格: `kk_string_compareTo_locale`（locale 依存）
- [ ] KSP-414: 数値パース（整数 radix 系）を Kotlin 化（`toInt(OrNull)(radix)`, `toLong…`, `toShort…`, `toByte…`, `toU*OrNull(radix)`, `toBoolean(Strict)(OrNull)`）
  - 削除 kk_*: `RuntimeStringConversion.swift` の該当関数（`rg -o '@_cdecl\("kk_string_to[A-Z][a-zA-Z]*(_radix)?"\)' Sources/Runtime/RuntimeStringConversion.swift` で列挙し Float/Double/BigDecimal/BigInteger を除く）
- [ ] KSP-415: 浮動小数・BigNum パースを `__kk_` 降格する（`toFloat(OrNull)`, `toDouble(OrNull)`, `toBigDecimal*`, `toBigInteger*`）
  - Foundation 依存のためブリッジ残留。`kk_string_toFloat*`, `kk_string_toDouble*`, `kk_string_toBigDecimal*`, `kk_string_toBigInteger*`, `kk_bignum_toString` を `__kk_` へ改名し、Kotlin 側 `@KsSymbolName` 宣言経由に置換
- [ ] KSP-416: エンコーディング系を `__kk_` 降格する（`toByteArray`, `encodeToByteArray`, `decodeToString`, `Charsets.*`）
  - トランスコードはブリッジ残留。`kk_charset_*` 9 関数と `kk_string_toByteArray*`, `kk_string_encodeToByteArray*`, `kk_bytearray_decodeToString*`, `kk_byteArray_toKString` を `__kk_` へ改名。公開 API 層（オーバーロード分岐・境界検査・例外）は Kotlin 化。インライン `kotlinTextSource` の同 API と統合（KSP-502 と調整）
- [ ] KSP-417: Unicode 正規化・codePoint・random を `__kk_` 降格する
  - `kk_normalization_form_*` 4 関数, `kk_string_normalize`, `kk_string_isNormalized`, `kk_string_codePointCount*` 3 関数, `kk_string_random(_random)` を `__kk_` へ改名（実装移植はしない）
- [ ] KSP-418: format/indent を完遂する（KSP-302 の残り + `String.format(_locale)` は `__kk_` 降格）
  - 対象: `RuntimeStringFormat.swift` の `kk_string_format`, `kk_string_format_locale`（降格）と残存 `__string_*` 旧ブリッジの命名統一

#### kotlin.collections [M3 実行体]（前提: KSP-305〜307。実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/`）

- [ ] KSP-421: List transform を完遂（`map`, `mapIndexed`, `mapNotNull`, `flatten`, `flatMap(Indexed)` + `*To` 変種）
  - 削除 kk_*: `kk_list_map`, `kk_list_mapIndexed`, `kk_list_mapIndexedTo`, `kk_list_mapNotNull`, `kk_list_mapNotNullTo`, `kk_list_mapTo`, `kk_list_flatten`, `kk_list_flatMap`, `kk_list_flatMapIndexed`, `kk_list_flatMapIndexedTo`, `kk_list_flatMapTo`（`RuntimeCollectionHOF.swift`）
- [ ] KSP-422: List fold/reduce/scan を Kotlin 化（`fold(Right)(Indexed)`, `reduce(Right)(Indexed)(OrNull)`, `runningFold/Reduce(Indexed)`, `scan(Indexed)`）
  - 削除 kk_*: 該当 19 関数（`rg -o '@_cdecl\("kk_list_(fold|reduce|running|scan)[a-zA-Z]*"\)' Sources/Runtime` で列挙）/ 既存 `ListAggregateHOF.kt` に追記
- [ ] KSP-423: List 検索・述語を完遂（`find(Last)`, `indexOf(First/Last)`, `lastIndexOf`, `contains(All)`, `any`, `all`, `none`, `count`, `binarySearch(By)`）
  - 削除 kk_*: `kk_list_find`, `kk_list_findLast`, `kk_list_indexOf`, `kk_list_indexOfFirst`, `kk_list_indexOfLast`, `kk_list_lastIndexOf`, `kk_list_contains`, `kk_list_containsAll`, `kk_list_any`, `kk_list_all`, `kk_list_none`, `kk_list_count`, `kk_list_binarySearch(_comparator/_compare)`, `kk_list_binarySearchBy(_fromIndex/_range)` / 既存 `ListSearchHOF.kt` に追記。等値判定コアは `__kk_values_equal`（新設）へ降格
- [ ] KSP-424: List アクセスを Kotlin 化（`getOrNull`, `getOrElse`, `elementAt(OrNull/OrElse)`, `first(OrNull)`, `last(OrNull)`, `single(OrNull)`）
  - ブリッジ残留: `kk_list_get`, `kk_list_size` は `__kk_` 降格（ストレージ直アクセス）。他は Kotlin 化して削除
- [ ] KSP-425: List associate/group/zip 系を Kotlin 化（`associate(By/With)(To)`, `groupBy(To)`, `withIndex`, `onEach(Indexed)`, `partition`, `unzip`）
  - 削除 kk_*: `rg -o '@_cdecl\("kk_list_(associate|group|withIndex|onEach|partition|unzip)[a-zA-Z]*"\)' Sources/Runtime` で列挙（約 19 関数）
- [ ] KSP-426: List sort/max/min を Kotlin 化（`sorted(By/With/Descending)` + `_primitive` 変種, mutable `sort*`, `max/min(By/Of/With)(OrNull)`）
  - 削除 kk_*: `RuntimeCollectionHOFMaxMin.swift` の sorted 系 18 + max/min 系 20（rg で列挙）。比較コアは KSP-309 の Comparator Kotlin 実装を利用
- [ ] KSP-427: List slice/take/drop を Kotlin 化（`take(Last)(While)`, `drop(Last)(While)`, `slice`, `subList`）
  - 削除 kk_*: `kk_list_take`, `kk_list_takeLast`, `kk_list_takeWhile`, `kk_list_takeLastWhile`, `kk_list_drop`, `kk_list_dropLast`, `kk_list_dropWhile`, `kk_list_dropLastWhile`, `kk_list_slice`, `kk_list_slice_iterable`, `kk_list_subList`
- [ ] KSP-428: List 集合演算・数値系を Kotlin 化（`plus`, `minus`, `intersect`, `union`, `subtract`, `distinct(By)`, `sum(Of/By)`, `average`, `reversed`, `asReversed`）
  - 削除 kk_*: 該当約 18 関数（rg で列挙）。`kk_list_shuffled(_random)` はエントロピー依存のため KSP-466 完了後に Kotlin 化
- [ ] KSP-429: List 変換・joinToString を Kotlin 化（`toMap`, `toSet`, `toHashSet`, `toMutableList/Set`, `joinTo(String)`, `orEmpty`, `component1-5`, `indices`, `lastIndex`, `isEmpty/isNotEmpty`）
  - ブリッジ残留: 新規コレクション生成コアのみ（KSP-305 の `__kk_` 群を利用）
- [ ] KSP-430: Map HOF を Kotlin 化（`filter(Keys/Values/Not)`, `map(NotNull)`, `mapKeys(To)`, `mapValues(To)`, `flatMap`, `forEach`, `any`, `all`, `none`, `count`, `maxByOrNull`, `minByOrNull`, `plus`, `minus`）
  - 削除 kk_*: `RuntimeCollectionHOF.swift` の `kk_map_*` HOF 18 関数 + `RuntimeSetAndMap.swift` の `kk_map_plus`, `kk_map_minus`
- [ ] KSP-431: Map lookup・変換を Kotlin 化（`getValue`, `getOrDefault`, `getOrElse`, `getOrPut`, `containsKey/Value`, `keys`, `values`, `entries`, `toList`, `toMutableMap`, `orEmpty`, `withDefault`）
  - ブリッジ残留: `kk_map_get`（キー探索コア）→ `__kk_map_get`、iterator 状態 → `__kk_map_iterator*`。他は Kotlin 化
- [ ] KSP-432: Set 全般を Kotlin 化（述語 13, HOF 6, `intersect`/`union`/`subtract`, `sorted(Descending)`, `maxOrNull`/`minOrNull`, 変換 4）
  - 既存 `SetHOF.kt` に追記。ブリッジ残留: 要素探索コア等の最小集合を `__kk_` 降格し残りの `kk_set_*` を削除（`rg -o '@_cdecl\("kk_set_[a-zA-Z_]+"\)' Sources/Runtime` で全列挙してから分類）
- [ ] KSP-433: Array HOF を Kotlin 化（`map(NotNull)`, `filter`, `fold(Indexed)`, `flatMap`, `reduce(Indexed)(OrNull)`, `forEach`, `any`, `all`, `none`, `find(Last)`, `count`, `binarySearch`, `sortedArrayWith`, `asSequence`, `joinToString`）
  - 削除 kk_*: `RuntimeCollectionHOFArray.swift` の 20 関数（rg で列挙）
- [ ] KSP-434: Grouping を Kotlin 化（`groupingBy`, `eachCount(To)`, `fold(To)`, `reduce(To)`, `aggregate(To)`）
  - 削除 kk_*: `RuntimeCollectionHOFGrouping.swift` の 11 関数 + `HeaderHelpers+SyntheticGroupingStubs.swift` の該当登録
- [ ] KSP-435: Iterable/Collection 汎用を Kotlin 化（`kk_iterable_*` 12 関数, `kk_collection_*` 6 関数）
  - ブリッジ残留: 型タグディスパッチが必要な `kk_collection_size` 等は `__kk_` 降格を検討（着手時に rg で分類し、分類根拠をタスク PR に記載）
- [ ] KSP-436: 可変操作の最小ブリッジを確定する（MutableList/Set/Map の `add`/`remove`/`clear`/`set`/`put` 系 33 関数）
  - 原則ブリッジ残留（ストレージ直接変異）: `kk_mutable_*` を `__kk_` へ一括改名し、`removeIf`/`retainAll`/`replaceAll`/`fill`/`addAll` 系など述語・複合系のみ Kotlin 化。`CallLowerer+MemberCallEmission.swift` の該当特例を Kotlin 宣言経由に置換

#### kotlin.sequences [M4 実行体]（KSP-441 が先頭。他は 441 完了後に並列可）

- [ ] KSP-441: Sequence 遅延 transform 基盤を Kotlin 化（`Sequence`/`Iterator` インターフェース + `map`, `filter` 系 transform）
  - 注意: object 式（匿名クラス）でパイプラインを表現する。コンパイラの object 式・ジェネリクス対応が不足していれば**ブロッカーとして報告し中断**
  - 対象 kk_*: `RuntimeSequence.swift` の transform 系（`kk_sequence_map*`, `kk_sequence_filter*`, `kk_sequence_withIndex`, `kk_sequence_flatMap*`, `kk_sequence_onEach*`, `kk_sequence_requireNoNulls` 等。rg で全列挙）
- [ ] KSP-442: Sequence terminal を Kotlin 化（`first*`, `last*`, `single*`, `elementAt*`, `find(Last)`, `contains`, `indexOf*`, `any`, `all`, `none`, `count`, `min*`, `max*`, `sum`, `average`）
  - 前提: KSP-441 / 既存 `SequenceAggregateHOF.kt` に追記
- [ ] KSP-443: Sequence 変換・集合演算を Kotlin 化（`toList`, `toMutableList`, `toSet`, `toMutableSet`, `toHashSet`, `toSortedSet`, `toCollection`, `toMap`, `flatten`, `unzip`, `union`, `intersect`, `subtract`, `plus*`, `minus`, `ifEmpty`, `constrainOnce`, `orEmpty`）
  - 注意: インライン `kotlinSequencesSource`（toList/toMutableList/toSet）と統合（KSP-503 と調整）
- [ ] KSP-444: Sequence association・minBy/maxBy を Kotlin 化（`associate*(To)`, `groupBy(To)`, `partition`, `joinTo(String)`, `sumOf/By(Double)`, `min/max(By/Of/With)(OrNull)`）
  - 削除 kk_*: `RuntimeSequenceAssociation.swift` の全関数（rg で列挙）
- [ ] KSP-445: Sequence fold/scan を Kotlin 化（`fold(Indexed)`, `reduce(Right)(Indexed)(OrNull)`, `scan(Indexed)`, `runningFold/Reduce(Indexed)`, `sorted*`）
  - 削除 kk_*: `RuntimeSequenceFoldScan.swift` の全関数
- [ ] KSP-446: Sequence `*To` 宛先変種を Kotlin 化（`filterTo` 等 11 関数、`RuntimeSequenceBuilders.swift` 内 STDLIB-SEQ-021 群）
- [ ] KSP-447: sequence{}/iterator{} ビルダーを (c) 残留分類として確定する
  - coroutine 機構と不可分（`kk_sequence_builder_*`, `kk_iterator_builder_*` 11 関数）。`__kk_` 降格 + `docs/stdlib-pipeline.md` §9 の (c) 表へ記載のみ。Kotlin 化はしない

#### kotlin.ranges [M6 実行体]（前提: KSP-312）

- [ ] KSP-451: Range プロパティ・membership を完遂（`first`, `last`, `start`, `endInclusive/Exclusive`, `count`, `isEmpty`, `contains`, `sum`, `reversed` の Int/Long/Char 版）
  - 削除 kk_*: `kk_range_first`, `kk_range_last`, `kk_range_start`, `kk_range_end`, `kk_range_endExclusive`, `kk_range_count`, `kk_range_isEmpty`, `kk_range_contains`, `kk_range_sum`, `kk_range_reversed`, `kk_long_range_*` 同系, `kk_char_range_isEmpty`
- [ ] KSP-452: for-in の range 特例を `.iterator()` 経路へ統一する
  - 変更: `ExprLowerer+ControlFlowAndBlocks.swift` の range 直接特例を、KSP-312 で配線した Kotlin `iterator()`（インライン展開）に置換。性能退行は diff_kotlinc + 簡易ベンチで確認し、退行時はループ最適化パスの課題として報告
  - 削除 kk_*: `kk_range_iterator`, `kk_range_hasNext`, `kk_range_next`, `kk_long_range_iterator`
- [ ] KSP-453: IntRange HOF を Kotlin 化（`RuntimeRangeIntRangeHOF.swift` の約 30 関数: `toList`, `forEach`, `map*`, `filter*`, `reduce*`, `fold*`, `find*`, `first/last(OrNull)(_predicate)`, `any`, `all`, `none`, `chunked`, `windowed`, `take`, `drop`, `average`, `sorted`, `toIntArray`）
  - 実装方針: `Iterable<Int>` の汎用 HOF へ委譲する形で個別 kk_* を不要化
- [ ] KSP-454: LongRange/CharRange HOF を Kotlin 化（`RuntimeRangeLongRange.swift` の HOF 群 + `kk_char_range_toList/forEach/take/drop/sorted`）
- [ ] KSP-455: UInt/ULong Range を Kotlin 化（`RuntimeRangeUIntULongRange.swift` の全 HOF/プロパティ約 80 関数）
  - 前提: 符号なし型のジェネリクス/演算対応を着手時に確認。困難なら (b)→(c) 再分類を提案して中断
- [ ] KSP-456: progression 構築系を Kotlin 化（`step`, `downTo`, `until`, `*_progression_fromClosedRange`）
  - 削除 kk_*: `kk_op_step`, `kk_op_downTo`, `kk_op_rangeUntil`, `kk_int/long/uint/ulong/char_progression_fromClosedRange` ほか（`kk_op_rangeTo` は演算子コアのため残留可）
- [ ] KSP-457: range random 系を Kotlin 化（前提: KSP-466。`kk_range_random*`, `kk_long_range_random*`, `kk_char_range_random*`, `kk_uint/ulong_range_random*`, `kk_random_nextInt/nextLong_rangeObject`）

#### kotlin.comparisons [M5 実行体]（前提: KSP-309）

- [ ] KSP-461: Comparator 群を完遂する（`nullsFirst/Last` 各種, `reversed`, multi-selector `compareBy`×3, `compareValues(By)`×6, `CASE_INSENSITIVE_ORDER`, primitive selector 版）
  - 削除 kk_*: `RuntimeComparator.swift` の残存全関数（trampoline 含む 53 − KSP-309 分。`rg -o '@_cdecl\("kk_(comparator|compareValues|comparable)[a-zA-Z_]*"\)' Sources/Runtime` で列挙）。比較コア `kk_comparable_compareTo` のみ `__kk_` 降格可

#### kotlin.random [M7 実行体]

- [ ] KSP-467: SecureRandom 互換層を `__kk_` 降格する（`kk_secure_random_*` 4 関数）

#### kotlin.time [M8 実行体]

- [~] KSP-472: Instant/Clock/measureTime のブリッジを確定する（2026-07-08、一部配線）
  - Kotlin 化済み: `kk_instant_epoch_seconds`, `kk_instant_nano_of_second`, `kk_instant_is_distant_past/future`, `kk_instant_plus/minus_duration`, `kk_instant_compare`, `kk_instant_until` を `__kk_instant_*` bridge（`HeaderHelpers+SyntheticInstantStubs.swift`）へ降格し、`Sources/CompilerCore/Stdlib/kotlin/time/Instant.kt` の拡張プロパティ/演算子/関数から呼ぶ形に配線。`elapsed()` はブリッジなしで `this.until(Instant.now())` として実装。`kk_timedvalue_value`/`kk_timedvalue_duration` も同様に `__kk_timedvalue_*` bridge 化し `Sources/CompilerCore/Stdlib/kotlin/time/TimedValue.kt` へ配線（`HeaderHelpers+SyntheticDurationStubs.swift`）
  - 副次修正: `HeaderHelpers+SyntheticClockStubs.swift` が `HeaderHelpers+SyntheticInstantStubs.swift` と同じ Instant companion/property/method を重複登録していたバグを解消（Clock 関連の登録のみに縮小、Instant symbol/type の再取得のみ残す）
  - 未達（技術的制約、direct stub のまま変更なし）: `kk_instant_now`, `kk_instant_from_epoch_millis`, `kk_clock_system_now` は companion/nested-object のファクトリメソッドで、このコンパイラの拡張関数宣言はレシーバ型として `Foo.Companion` を解決できない（`fun Foo.Companion.f(): Foo` は "Unresolved type 'Companion'" になる）ため Kotlin source の拡張として書けない。**訂正(2026-07-10 実測)**: 単純ネストクラスの `fun Outer.Inner.f()` は**動作する**（旧記載は誤り）— 失敗するのは companion レシーバのみ（KSWIFTK-SEMA-0024）。ブロッカーは KSP-CAP-003 として独立起票。`kk_clock_now` は `Clock` がユーザー実装可能な interface であり `now()` の member dispatch が必須。`kk_measureTime`/`kk_measureTimedValue` は `CallLowerer+StdlibLoops.swift` の KIR 特殊インライン展開が `stdlibSpecialCallKind`（関数名ベース）でディスパッチしており、direct stub 名を変更すると壊れるため対象外。`kk_timedvalue_new` は `measureTimedValue` の KIR lowering からのみ呼ばれる内部コンストラクタで、Kotlin source から到達しないため対象外
  - 前提追記: 残る配線は KSP-CAP-003 の解消後に実施

#### kotlin.uuid [M12 実行体]

- [ ] KSP-507: kotlin.uuid.Uuid の実 API 未実装分を追加する（KSP-310 訂正のフォローアップ）
  - 対象: `mostSignificantBits`/`leastSignificantBits` を `public` から `@PublishedApi internal` へ変更（KSwiftK がバンドル stdlib とユーザーコード間のモジュール境界可視性を実際に強制するか未検証のため、まず spike で確認する）
  - 対象: `toULongs`, `toUByteArray`, `fromUByteArray`, `fromULongs`, `toHexDashString`, `generateV4()` を追加
  - 対象外（別途再調査してから着手）: `generateV7()` / `generateV7NonMonotonicAt()` は `kotlin.concurrent.atomics.AtomicLong` と `kotlin.time.Clock`/`Instant` に依存。Atomics サポートの有無が未確認、Clock/Instant も KSP-472 で部分配線のみのため、実現可能性を先に確認する
  - 前提: KSP-309（Comparators 配線、`naturalOrder`）が未着手のため、`naturalOrder<Uuid>()` を使う置き換え例は現状 `Uuid.compareTo()` 直接呼び出しで代替中
  - ブロッカー候補（2026-07-09 発見、要再調査）: `toLongs`/`toULongs` と同型の `inline fun <T> foo(action: (X, Y) -> T): T` パターンで、ラムダ本体が (a) 引数をそのまま返す恒等関数（`{ m, l -> m }`）→ `KSWIFTK-TYPE-0001: Conflicting bounds ... T is not a subtype of Long` で失敗、(b) `Uuid.fromLongs(m, l)` や `Pair(m, l)` のようなネストしたコンストラクタ/コンパニオン呼び出し → `KSWIFTK-SEMA-0002/0003` で失敗、(c) `Boolean` を直接返す（`{ m, _ -> (...).toInt() == 4 }`）→ コンパイル・実行は成功するが文字列補間時に `true`/`false` ではなく `1`/`0` を出力（プリミティブが `T` を経由してボックス化される際の unboxing 不整合と推測、[[primitive-autoboxing-mutable-collection-add]] や [[comparison-unboxing-peer-type]] と同系統）。`toLongs` 自体は `m + l` のような二項演算のみを返す形（ジェネリック呼び出しの外側で比較・再構築する）であれば安全に動作することを確認済み（`Scripts/diff_cases/uuid_basic.kt` 参照）。`toULongs`/`toUByteArray` 等を実装する際は同じ制約に当たる可能性が高く、Sema/TypeCheck の型変数解決（`CallTypeChecker` 系）と ABI Lowering のプリミティブ boxing 経路の両方を先に調査すること
- [ ] KSP-508: `ByteArray.getUuid`/`uuid`/`putUuid` を実 API（`ByteBuffer.getUuid`/`putUuid`）に置き換える（2026-07-09 マージ時発見、要再調査）
  - 問題: KSP-476（#4605）が実装した `kotlin.uuid.ByteArray.getUuid(offset)` / `ByteArray.uuid(at)` / `ByteArray.putUuid(at, uuid)` は実際の `kotlin.uuid` パッケージには存在しない。kotlinc 2.4.0 の `kotlin-stdlib-sources.jar`（`jvmMain/kotlin/uuid/UuidJVM.kt`）で裏取りした実 API は `java.nio.ByteBuffer` の拡張関数 `ByteBuffer.getUuid()` / `ByteBuffer.getUuid(index: Int)` / `ByteBuffer.putUuid(uuid): ByteBuffer` / `ByteBuffer.putUuid(index, uuid): ByteBuffer`（いずれも `@SinceKotlin("2.4")` `@WasExperimental(ExperimentalUuidApi::class)`）であり、`ByteArray` ではなく `ByteBuffer` がレシーバ。`version`/`variant`/`nameUUIDFromBytes` と同型の「実 API 未確認のまま実装」ミス
  - 影響範囲: `Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt`（`ByteArray.getUuid/uuid/putUuid` 拡張・`readUuidFromBytes` ヘルパ）/ `Tests/CompilerCoreTests/KIR/BuildKIRRegressionTests+Uuid.swift`（`testUuidByteArrayExtensionsAndJavaInteropLowerThroughKotlinSource`）/ `Tests/CompilerCoreTests/Sema/UuidGetUuidSemaTests.swift` / `Tests/CompilerCoreTests/Sema/UuidPutUuidSemaTests.swift` / `Tests/CompilerCoreTests/Sema/UuidAPISurfaceInventoryTests.swift`（`getUuid`/`uuid`/`putUuid` 3エントリ）
  - 確認済み（2026-07-09、kotlinc-jvm 2.4.0 で実測）: `Scripts/diff_cases/uuid_put_uuid.kt` は SKIP-DIFF が付いておらず現在 diff_kotlinc.sh の実 parity 対象だが、実 kotlinc は `import kotlin.uuid.uuid` を `unresolved reference 'uuid'`、`buf.putUuid(0, original)` を「`fun ByteBuffer.putUuid(uuid: Uuid): ByteBuffer` に receiver type mismatch」で拒否し、確実にコンパイル失敗する。CLAUDE.md の「リファクタ PR 必須ゲート」（`bash Scripts/diff_kotlinc.sh Scripts/diff_cases` を green にする）を満たそうとすると即座に踏むアクティブな既知バグ
  - 対応方針（未着手、要検討）: (a) `ByteArray.getUuid/uuid/putUuid` を撤去し `ByteBuffer.getUuid/putUuid` を新規実装（`java.nio.ByteBuffer` interop の有無を先に確認 — 無ければブロッカー）、(b) 撤去のみでこの PR 時点では未配線として KSP-310/476 のスコープから正式に除外、のいずれか。影響範囲が広いため本 PR（マージコンフリクト解消）の対象外とし、別 PR に切り出す

#### kotlin.io [M 番号なし・新設]（棚卸し 2026-07-01: File I/O 58 / Base64 26 / HexFormat 16 の計 100 @_cdecl）

- [ ] KSP-484: File I/O の syscall 層を `__kk_` 降格する
  - 対象（ブリッジ残留・改名のみ）: 構築 `kk_file_new(_parent_child)`, 読み書き `kk_file_readText/readBytes/readLines/writeText/appendText/writeBytes/appendBytes`, 存在判定 `kk_file_exists/isFile/isDirectory/canRead/canWrite/canExecute/length/lastModified`, FS 操作 `kk_file_delete/mkdirs/createNewFile/listFiles`, 走査 `kk_file_walk(TopDown/BottomUp)`, `kk_file_tree_walk_sortedBy`, ストリーム/リソース/temp 系（`rg -o '@_cdecl\("kk_(file|files|io|classloader|resource|input_stream|output_stream)[a-zA-Z_]*"\)' Sources/Runtime/RuntimeFileIO.swift` で全列挙）
  - 公開 API 層（`forEachLine`/`useLines`/`readLines` のイテレーション・例外規約・デフォルト引数分岐）は Kotlin 化し、ブロック単位 I/O のみブリッジに残す
  - 手順: T / diff: `file_*.kt` 21 ケース（既存）全 green 維持

#### kotlin.text.Regex [M 番号なし・新設]（棚卸し 2026-07-01: 39 @_cdecl。正規表現エンジン = NSRegularExpression はブリッジ残留）

- [ ] KSP-486: MatchResult/MatchGroup 層を Kotlin 化する（純ロジック約 20 関数）
  - 削除 kk_*: `kk_match_result_value/groupValues/range/groups/component1/component2/next`, `kk_match_group_collection_get_at/get/size`, `kk_match_group_value/range`, `kk_match_result_destructured(_match)`, `kk_match_result_destructured_component1..9`, `kk_regex_pattern`, `kk_regex_options`, `kk_regex_group_names`（`RuntimeRegex.swift`）
  - 内部のマッチ位置データ取得のみ `__kk_` 最小ブリッジに残す / 手順: T / diff: `regex_named_groups.kt` ほか既存 10 ケース
- [ ] KSP-487: Regex 公開 API 層を Kotlin 化し、エンジンを `__kk_` 降格する
  - Kotlin 化: `String.toRegex`×3 / `matches` / `contains` / `replace(First)` / `split` のオーバーロード分岐・入力検証（下敷き: 死蔵 `Stdlib/kotlin/text/Regex.kt` はコメントアウト状態 — 実質新規実装）
  - `__kk_` 降格: `kk_regex_create(_with_option/_with_options)`, `kk_regex_from_literal`, `kk_regex_find(All)`, `kk_regex_matchEntire`, `kk_regex_matches`, `kk_regex_containsMatchIn`, `kk_regex_replace_lambda`, `kk_string_*_regex` 系エンジン呼び出し
  - 削除: `HeaderHelpers+SyntheticRegexStubs.swift` の該当登録 / 手順: T

#### kotlin.properties [M 番号なし・新設]（棚卸し 2026-07-01: `RuntimeDelegates.swift`。`by` 式は `StdlibDelegateLoweringPass` が call site を直接書き換える構造）

- [ ] KSP-491: Lazy / Delegates を Kotlin 化する
  - 下敷き: 死蔵 `Stdlib/kotlin/LazyDelegate.kt`, `properties/Properties.kt`, `properties/Delegates.kt`, `properties/ObservableProperty.kt` → `Sources/CompilerCore/Stdlib/kotlin/properties/` へ移設
  - Kotlin 化: `ReadOnlyProperty`/`ReadWriteProperty` インターフェース、`ObservableProperty`（beforeChange/afterChange）、`Delegates.observable/vetoable/notNull`、`lazy(mode)` の `NONE`/`PUBLICATION` モード
  - ブリッジ残留: `SYNCHRONIZED` モードのロックのみ `__kk_lazy_sync_*`（新設）
  - 変更: `Sources/CompilerCore/Lowering/StdlibDelegateLoweringPass.swift` の `kk_lazy_create`/`kk_observable_create`/`kk_vetoable_create`/`kk_notNull_create` 書き換え特例を、Kotlin 宣言の通常解決（`getValue`/`setValue` operator 規約）へ置換
  - 削除 kk_*: `kk_lazy_create/of/get_value/is_initialized`, `kk_observable_create/get_value/set_value`, `kk_vetoable_*` 3, `kk_notNull_*` 3（`RuntimeDelegates.swift`）/ `HeaderHelpers+SyntheticPropertyDelegateStubs.swift` の該当登録
  - 注意: operator 規約による delegate 解決がコンパイラ未対応なら**ブロッカーとして報告し中断** / diff: `delegate_lazy.kt`, `delegate_observable.kt`, `delegate_vetoable.kt`, `delegates_not_null.kt`（既存）/ 手順: T

#### kotlin.reflect [M 番号なし・新設]（棚卸し 2026-07-01: メタデータレジストリ依存のためブリッジ色が濃い）

- [~] KSP-496: KClass 公開 API 層を Kotlin 化し、メタデータレジストリを `__kk_` 降格する
  - 完了: 下敷き2ファイルを `Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt`/`KClassMemberIntrospection.kt` へ移設・実配線（ルート `Stdlib/` の死蔵版は削除）。Kotlin 化: `simpleName`/`qualifiedName`/`isInstance`/真偽値フラグ12種（isFinal/isOpen/isAbstract/isData/isSealed/isValue/isEnum/isInterface/isObject/isInner/isCompanion/isFun。チケット記載は「11種」だが実装対象は`CompilerKnownNames.swift`基準の12種）/`visibility`/`annotations`。`__kk_` 降格: rg で全列挙した `kk_kclass_*`/`kk_type_token_*`/`kk_ktype_*`/`kk_ktypeprojection_*`/`kk_kfunction_*`/`kk_kparameter_*`/`kk_kconstructor_*`/`kk_annotation_*`（`RuntimeStringArray.swift`/`RuntimeReflection.swift`、計 ~65 個。`cast`/`safeCast` の実体もリネーム済み）をリネームし、`RuntimeABISpec` 側も追従（未登録だった `kk_kclass_nested_classes` の欠落も是正）。
  - 「全部対応して」指示を受けた追加調査で、残り3カテゴリの根本原因を深掘りし、うち2件を実際に修正した（詳細は下記）。全カテゴリの完全移行には至っていないが、根本原因の解像度は大きく上がっている。
  - **修正済みの根本原因バグ（3件、いずれも `Sources/CompilerCore/` 内）**:
    1. `String::class`/`Char::class`/`Any::class` のように、`HeaderHelpers.ensureClassSymbol` が member 宣言（CharSequence 適合など）を持たせるためだけに登録する `kotlin.<Name>` 偽装 `.class` シンボルが存在する組み込み型で、`T::class` のスコープ解決がこの偽装シンボルを builtin 名フォールバックより先に見つけてしまい、`classRefTargetType` が偽装 nominal 型（`.classType`）になる問題。これにより `String::class.isInstance("x")` が `RuntimeTypeCheckToken.encode` で `nominalBase` として誤符号化され、常に `false` を返していた（正しくは `stringBase`）。修正: `RuntimeTypeCheckToken.encode`（`Sources/CompilerCore/KIR/RuntimeTypeCheckToken.swift`）に `encodeBuiltinDisguisedNominal` を追加し、`.nominal` 分類時にこの偽装を検出して builtin base へフォールバックするようにした。回帰テスト `testBuiltinClassRefTokenMatchesPrimitiveBase`（`Tests/CompilerCoreTests/KIR/RuntimeTypeCheckTokenTests.swift`）追加済み。
    2. 上記と同根で、`TypeSystem.isSubtype` が偽装 nominal 型（例: `String` の `kotlin.String` 偽装シンボル）と canonical builtin 型（`.stringStruct` 等）を無関係な型として扱っていたため、`fun <T : Any> KClass<T>.cast(value: Any?): T = value as T` を `String::class.cast(v)` のように呼ぶと、ジェネリック制約ソルバが `KSWIFTK-TYPE-0001: Conflicting bounds for type variable`（`Class#N is not a subtype of Class#N & String`）を出して失敗していた。修正: `TypeSystem`（`Sources/CompilerCore/Sema/TypeSystem/TypeSystem.swift`）に `stringClassSymbol`/`charClassSymbol`/`anyClassSymbol` を追加（`HeaderHelpers+SyntheticStringStubs.swift`/`+SyntheticCharStubs.swift`/`HeaderHelpers.swift` の登録箇所で設定）し、`Subtyping.swift` の `isSubtype` 冒頭で `normalizeBuiltinDisguisedClassType` により両辺を正規化するようにした。`fun <T : Any> KClass<T>.myCast(value: Any?): T = value as T` を `String::class.myCast(v)`（期待型 `String`）から呼ぶケースで実際にコンパイル・実行成功を確認済み。
    3. （KClass 無関係の汎用バグ、上記調査中に副産物として発見）`fun <T> foo(value: Any?): T { return value as T }` のように非 reified 型パラメータへ `as T` する「unchecked cast」で、`RuntimeTypeCheckToken.encode` が `.typeParam` を `unknownBase`(=0) として符号化し、`kk_op_is` の `default: return 0` に落ちて **常に ClassCastException を投げていた**（本来 JVM 型消去と同じく無条件成功すべき）。`is T`（非 reified）は既に `KSWIFTK-SEMA-0084` でコンパイルエラーになるためこの土台は `as`/`as?` 経由でしか到達しないことを確認済み。修正: `ExprLowerer+ControlFlowAndBlocks.swift` の `.asCast` lowering で、ターゲット型が非 reified 型パラメータの場合はランタイム呼び出しを発行せず `.copy` 命令で値をそのまま通すようにした。
  - **未完了（根本原因は特定したが、このセッションでは着手を見送った）**:
    - `members`/`constructors`/`primaryConstructor`/`properties`/`memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/`declaredMemberFunctions`/`nestedClasses`/`supertypes`: `RuntimeKFunctionBox`/`RuntimeKPropertyStub`等のランタイムハンドルが真の interface 適合性チェック（`is`/`as`）に未対応な点は変わらず。ただし **実現可能な道筋は判明した**: `Sources/Runtime/RuntimeCollectionHOF.swift`/`RuntimeCollectionHelpers.swift` に既に `IndexedValue`/`Map.Entry` 用の前例があり、`runtimeRegisterObjectType(rawValue:classID:)` + `runtimeRegisterTypeEdge(childTypeID:parentTypeID:)`（`RuntimeHelpers.swift`）という汎用機構が「ランタイム専用オブジェクトに Kotlin 側の nominal 型 ID を後付けでタグ付けし、supertype グラフに登録する」ことを既に実現している。かつ `KFunction <: KCallable` 等の supertype 関係は `HeaderHelpers+SyntheticPropertyDelegateStubs.swift` の `addSyntheticDirectSupertypes` で **Sema レベルでは既に正しくモデル化済み**（コンパイル時の型システムは対応しているが、ランタイム側のオブジェクトタグ付けと、`KCallable.name` 等の共有メンバーの「実体の型に応じた分岐呼び出し」が未実装、というのが正確なギャップ）。次にやる場合: (1) 各リフレクション interface の nominal 型 ID を `runtimeStableNominalTypeID(fqName:)` で計算し起動時に一度登録 (2) `RuntimeKFunctionBox` 等の生成箇所を `registerRuntimeObject(_:typeID:)` 経由に変更 (3) `name`/`visibility`/`annotations` 等の共有メンバーを「複数のBox型を順に `tryCast` する」ディスパッチ関数に書き換え。対象メンバーの数が多く、後方互換の検証（既存 diff ケースには本挙動をカバーするものが無い）も含めると一定規模の別タスクとして切り出すのが妥当。
    - `cast`/`safeCast`: 上記の根本原因修正 (2) により「型変数の境界矛盾」自体は解消したが、Kotlin ソース化するには `fun <T : Any> KClass<T>.cast(value: Any?): T = __kk_kclass_cast(this, value) as T` のように **スロー可能な `__kk_kclass_cast`（`outThrown` 引数を持つ3引数 Swift 関数、`RuntimeABISpec` 上 `isThrowing` デフォルト `true`）を bundled Kotlin ソースから `@KsSymbolName` 経由で呼ぶ**必要がある。この形（stdlib ソースからの throwing external 呼び出し）の前例が現状の bundled Kotlin ソース全体に一件も無く、コンパイラの一般呼び出し lowering が `RuntimeABISpec.isThrowing` を正しく参照して `outThrown` 引数を自動挿入するかが未検証（`CallLowerer+MemberCallEmission.swift` の `throwingCallees` はメンバーコール専用のハンドキュレートされたリストで、`__kk_kclass_cast` は含まれていない）。誤ると ABI 不整合（引数個数不一致によるスタック破壊）のリスクがあるため、このセッションでは検証済みの安全な移行手段が確立できず見送った。次にやる場合はまず「throwing な `@KsSymbolName` external を bundled stdlib から呼ぶ」ことの可否を独立した最小ケースで検証すべき。
    - `findAnnotation`: reified 型引数を要求する点に加え、見つかったアノテーションのランタイム表現 `RuntimeAnnotationBox`（`Sources/Runtime/RuntimeTypes.swift`）が引数を汎用文字列配列としてしか保持しないため、`findAnnotation<A>(): A?` を精密な `A?` 型で返しても `A` の宣言プロパティへの実アクセスは機能しない（members/constructors と同根の「ランタイムハンドルが本物の Kotlin オブジェクトとして振る舞わない」問題）。現状の compiler 特例は正直に `Any?` を返しているため、`if (found != null)` のような存在確認以上の用途は元々サポートされていない。
    - `findAssociatedObject`: 単体では戻り値が `Any?`（`T` へのキャスト不要）かつ実体が `runtimeObjectRaw=` プレフィックス経由で本物のオブジェクトハンドルを返す設計のため、Kotlin ソース化自体は上記2つより低リスクに見えたが、**既に `HeaderHelpers` 側で reified・inline・`@ExperimentalAssociatedObjects` opt-in 要求を満たす専用の synthetic シンボルが登録済み**（`Tests/CompilerCoreTests/Sema/ReflectFindAssociatedObjectSyntheticTests.swift` で検証されている）であることが判明。Kotlin ソースへの置き換えはこの opt-in 強制や reified 型引数の意味論を含めて忠実に再現する必要があり、当初想定より複雑と判断してこのセッションでは見送った（着手しかけた変更は復元済み）。
  - **見つかったが対象外として別タスクに切り出したバグ（2件、いずれも KClass 無関係の汎用コンパイラバグ）**: (1) ジェネリック関数内の文/式に `@Suppress("UNCHECKED_CAST")` を付けると `KSWIFTK-TYPE-0001`/`KSWIFTK-SEMA-0022` 等の誤エラーが発生する（HEAD でも再現する既存バグ、確認済み）。(2) `inline fun <reified T>` の本体で発生した例外が呼び出し元の `try`/`catch` で捕捉されずクラッシュする（インライン展開と例外処理範囲の相互作用が疑われる）。
  - 副産物として発見・修正した既存バグ（他の bundled Kotlin 拡張全般に影響しうる）: (1) `kotlin.reflect` が `ScopeBuilder.swift` のデフォルトインポートパッケージ一覧に無く、`kotlin.reflect` 配下の拡張がスコープ解決で見つからなかった (2) `BundledDeclarationIndex.receiverOwnerFQName` が `.kClassType`（`T::class` 用の内部専用型表現）を未処理で、`KClass<...>` レシーバの拡張が優先規則の索引に正しく載っていなかった (3) `RuntimeABISpec+Operator.swift` の `__kk_kclass_find_associated_object` 登録に `isThrowing: false` が抜けており、実体（2引数、`outThrown` 無し）と齟齬していた。
  - diff: `kclass_basic.kt`, `reflect_kclass_ktype.kt`, `kclass_type_model.kt`, `type_reflection.kt`, `reflection_dynamic_call.kt` green（移行後も kotlinc と一致）。`kclass_members.kt`/`kclass_ktype_basic.kt`/`annotation_reflection.kt` は変更前から kotlinc 側が別理由（`kotlin.reflect.full` 未 import 等）で失敗しており未変更（git stash で移行前と同一エラーを確認済み）。

#### kotlin.coroutines / Flow / Channel [(c)/(b) 分類確定 + (b) 群のみ移行]（棚卸し 2026-07-01: スタブ 23 ファイル 10,849 行 / Runtime 7 ファイル 279 @_cdecl）

> 引き継ぎ注記(2026-07-10): 旧 `STDLIB-CORO-001`（`[~]` のまま 2026-07-07 #4582 で削除）の残課題は KSP-498/499 + KSP-674〜679 が正式に引き継ぐ。SharedFlow/StateFlow 等の細分は KSP-W6 の concurrent 節を参照。

- [ ] KSP-499: Flow オペレータ (b) 群を Kotlin 化する
  - 前提: KSP-498 + suspend fun を含む bundled Kotlin ソースのコンパイル対応を確認（未対応なら**ブロッカーとして報告し中断**）
  - **既知のブロッカー（2026-07-08 コード確認済み）**: `Sources/CompilerCore/Lowering/CoroutineLoweringPass+Flow.swift` の
    `lowerFlowExpressions` が `map`/`filter`/`take`/`toList`/`first`/`merge`/`zip`/`combine`/`flatMapConcat/Merge/Latest`/
    `debounce` 等を、Sema が解決した callee symbol を無視して「レシーバの flow provenance + 呼び出し名の文字列一致」だけで
    `kk_flow_*` へ構造的に書き換える（`FlowLoweringNames` 初期化コード参照）。bundled Kotlin 側にこれらの名前で実装を
    追加しても Lowering 段階で無条件に上書きされ呼ばれない。着手前に、このパスを対象外にする変更（同一 PR 必須）と
    ダミー実装差し替えテストでの再検証が必要。詳細: `docs/stdlib-pipeline.md` §9 KSP-498 セクション「Flow (b) 移行の前提条件」
  - 対象: `kk_flow_to_list`, `kk_flow_fold`, `kk_flow_first`, `kk_flow_merge`, `kk_flow_zip`, `kk_flow_combine` + per-element オペレータ（`RuntimeCoroutineFlow.swift` の 34 関数から (b) 分を rg で列挙）。`kk_flow_create/emit/collect` は (c) ブリッジ経由
  - diff: `flow_basic.kt`, `flow_builders.kt`, `flow_advanced_operators.kt` ほか既存 6 ケース / 手順: T
  - 🟡 **前提解決の根本修正を実施中（2026-07-08）**: 当初「着手不可」と判断したブロッカーのうち、以下の基盤修正が完了・実機検証済み。KSP-499 本体（実際の (b) 群 Kotlin 実装 + stub/cdecl/ABI 削除）はこれから着手。
    1. **Lowering が解決済みシンボルを無視して呼び出し名で書き換える問題 → 🟢 修正済み**: `FlowLoweringPass.swift` と `CoroutineLoweringPass+FlowInstructionRewrite.swift`（`rewriteFlowInstructions`）に、Sema が実宣言（`SemaModule.bundledIndex`、bundled Kotlin ソース由来）へ解決した呼び出しは構造的書き換えをスキップするガードを追加。加えて `CallTypeChecker+MemberCallInferenceCollectionFlow.swift`（`tryBuiltinFlowMemberCall` 呼び出し前）と `CallLowerer+MemberCalls.swift`（KIR 層の `transform`/`single` 特例）にも同様のガードを追加し、Sema・KIR・Lowering の3層すべてで「bundled/ユーザーの実宣言が解決済みシンボルとして存在するなら、ハードコードされた Flow intrinsic 特例より優先する」を実現。前提として `Flow`/`SharedFlow`/`StateFlow`/`MutableSharedFlow`/`MutableStateFlow` に実ジェネリクス型引数（`HeaderHelpers+SyntheticIterableRegistry.swift` の `Iterable<E>` と同パターン）を導入済み（従来は `ClassType.args: []` で要素型は side-table 管理のみだった）。実機再検証: 同じ実証手順（`suspend fun <T> Flow<T>.toList(): List<T> = listOf()` を **bundled** Stdlib 側（`BundledDeclarationIndex` はユーザーファイルでなく bundled ファイルのみを対象とするため要注意）に置いて `flowOf(1, 2, 3).toList()` を実行）で `RESULT=[]`・`MARKER_HIT=true` を確認 — ダミー実装が正しく優先されるようになった。副次発見: `.call`（トップレベル関数形式）は元々各分岐で `symbol == nil` を要求済みだったが、`.virtualCall`（`someFlow.map { }` という実際に最も使われるメンバー呼び出し構文）にはこのチェックが存在せず、新規追加が必要だった。検証: フル `swift_test.sh`（4385テスト、既知フレーキー1件除き green）・Golden 全件（295 Sema ケース含めゼロ diff）で確認。`diff_kotlinc.sh` 669 ケースは Stage 1（Bug A 単体）時点で green 確認済みだが、Stage 3（本ゲート追加後）の全件再確認は複数の並行セッションによるマシン競合のため未完了 — 次回セッションで低負荷時に再実行すること。
    2. **`kk_flow_fold`/`kk_flow_reduce`/`kk_flow_count` はコンパイラ側から到達不能**: Runtime の `@_cdecl` 実装・`RuntimeABISpec` エントリ・`Tests/RuntimeTests/RuntimeFlowTests.swift` の直接呼び出しテストは存在するが、Sema/KIR/Lowering のどこにもこれらを emit するコードが無い（`rg 'kk_flow_fold|kk_flow_reduce|kk_flow_count' Sources/CompilerCore` が 0 件）。つまり現状 `Flow<T>.fold(...)` は `.kt` から呼び出す経路が存在せず、「既存ネイティブ挙動を Kotlin に置き換える」という前提自体が `fold` には当てはまらない。既存 diff 6 ケースもこれらを使用していない。
    3. **ジェネリック高階関数のラムダ内演算子/メンバ解決バグ（suspend 有無に関係なく再現）** — 🟢 **演算子部分は修正済み（2026-07-08）**: 根本原因は `CallTypeChecker+LambdaReturnTypeOverload.swift` の `lambdaLiteralExpectedType()` がラムダ引数の期待型を計算する際、呼び出し先の非ラムダ引数から既に推論済みの型引数代入（例 `f(41) { ... }` の `T=Int`）を適用せず、未代入の `TypeParamType` をそのままラムダ引数の型にしていたこと。対処: `Resolution.swift` に `OverloadResolver.probeArgumentTypeSubstitution(...)`（非ラムダ引数だけから型変数代入を導出する軽量プローブ、`decomposeSubtypeConstraint`/`ConstraintSolver` を流用）を追加し、`CallTypeChecker+LambdaReturnTypeOverload.swift` に `applyInferredArgumentTypeArgs()`（`applyExplicitTypeArgs`/`applyReceiverClassTypeArgs` に続く第3の代入パス）を追加して配線。`f(41) { v: Int -> v + 1 }` は修正済みで動作を確認。AST 側のラムダ引数明示型注釈の保持（`skipTypeAnnotationIfPresent` が捨てている）は見送り — 本修正で repro は解決するため不要と判断。
       - 🟡 **残存する別問題（未修正、意図的に見送り）**: メンバー関数呼び出し（`.uppercase()`, `.length`, ユーザー定義クラスの任意メソッド等 — Int/Long 等プリミティブの特例ディスパッチ経路を通らないもの）は、ジェネリック HOF のラムダ本体内では `KSWIFTK-SEMA-0002: No viable overload found for call.` で依然失敗する。根本原因を特定済み: `Resolution.swift` の `evaluateCandidate` が、ラムダ本体の呼び出しに対して「外側の未束縛な型パラメータ（例 `R`）」を `expectedType` としてそのまま渡し、`signature.returnType <: R` を通常の（フリーではない）制約として追加するため、`describe(): String` のような具体型を返す候補が「`String` は `R` の部分型ではない」として誤って `.rejected` される。`inferLambdaLiteralExpr`（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）には既に同種の「期待戻り値型が無制約の型パラメータなら制約を課さない」ガードが存在するが、`evaluateCandidate` 側には無い。**一度この同じガードを `evaluateCandidate` に追加して検証したが、`Int.plus(1)` のような別の正常ケースを壊し（誤って文字列関連の codegen 経路に迷い込み無限に近い遅延を起こす）、安全に一般化できないことを確認済みのため revert 済み**。真の修正には「`expectedType` の無制約型パラメータが REALLY 無関係な外側スコープのものか」をもっと正確に判定する必要があり、本タスクの想定規模を超える別問題として切り出す。KSP-499 の Kotlin 実装（Stage 4-6）では、アキュムレータ関数は `operation(acc, v)` のような関数値呼び出し（この問題の対象外）で書き、生成コード内でジェネリック型 T 自体のメンバー関数呼び出しは極力避ける設計とする。
    4. **bundled Stdlib に `suspend` の前例が無い** — 🟢 **検証済み（2026-07-08）**: `Sources/CompilerCore/Stdlib/kotlinx/coroutines/flow/` に一時ファイルを置いて実機確認。bundled ソースでの `suspend fun`（ジェネリック含む）は正常にコンパイル・実行できる（`suspend fun <T, R> f(v: T, g: suspend (T) -> R): R` 相当が動作）。前例が無かっただけで、経路自体に問題は無い。
    - 対応が必要な前段作業（いずれも本タスクの想定規模を超える別タスク相当・進行中）: (a) 上記 Lowering 2 パスを「bundled/実体宣言優先」に改修 — 未着手 (b) ジェネリック高階関数のラムダ内演算子/メンバ解決バグの修正 — 演算子部分は修正済み、メンバー呼び出し部分は既知の限界として残存 (c) KSP-498 の正式な分類表作成 — 未着手。

### KSP-W5: 後始末（W3/W4 の対応タスク完了後）

- [ ] KSP-501: `BundledKotlinStdlib.kotlinCollectionsSource` を .kt 化する（`count`/`any`/`all`/`none`/`sumOf`/`maxByOrNull`/`minByOrNull` → `collections/ListAggregateHOF.kt` へ移設。live ツリーとの重複なしは 2026-07-01 に確認済み）
- [ ] KSP-502: `kotlinTextSource` を .kt 化する（`repeat`/`reversed`/`padStart`/`padEnd`/`encodeToByteArray`×3/`decodeToString`×4/`indent`×2 → `text/` 配下へ。**注意**: `trimIndent`/`trimMargin`/`prependIndent`/`replaceIndent`/`replaceIndentByMargin` は KSP-302 で処理済みのはず — 残っていれば重複させず統合）
- [ ] KSP-503: `kotlinSequencesSource`/`kotlinTimeSource` を .kt 化し、`BundledKotlinStdlib.swift` と `FrontendPhases.swift` の `residualSources` 注入を削除する
  - 完了: `rg 'BundledKotlinStdlib' Sources` 0 件 + G
- [ ] KSP-504: ルート `Stdlib/` 死蔵ツリー（35 ファイル）を整理する
  - 手順: (1) `Package.swift` の `resources: [.copy("Stdlib")]` が `Sources/CompilerCore/Stdlib` を指すこと（ルートではない）を確認 (2) 各 .kt を「対応 KSP タスクの下敷きに使う / 即削除」に分類（W3/W4 の該当タスクへ移設済みのものから削除） (3) `git rm -r Stdlib/`
  - 完了: ルート `Stdlib/` が存在しない + G
- [ ] KSP-505: `excludedBundledStdlibFiles` 機構を撤廃し、ファイル名を本家準拠へリネームする
  - 前提: W3 全完了。手順: (1) セットが空であることを確認して機構ごと削除 (2) `text/Strings.kt`, `collections/Collections.kt` 等 kotlin-stdlib 本家のファイル構成へ統合リネーム（`docs/stdlib-pipeline.md` §6） (3) U で golden 更新

### KSP-W6: 追補モジュール移行（ギャップ監査 2026-07-10。手順は全て T。粒度ルール適用済み = 1タスク1PR）

> 2026-07-10 監査で判明した「(b) 分類なのに KSP タスクが無い」領域 + (c) 再分類監査（厳格原則: Swift 残留は言語コア/GC・continuation・メタデータ/OS syscall のみ）で b-reclass になった領域の実行体。各タスクの削除対象・特例位置は監査時点で実コード検証済み — 着手時は rg で再固定する。

#### コア util（kotlin 直下）

- [ ] KSP-601: let/also/takeIf/takeUnless を Kotlin 化する（非レシーバ形ラムダのみで CAP 不要。実装先 `kotlin/Standard.kt` 新設。kk_* ゼロ（全インライン特例）— 削除対象は `HeaderHelpers+SyntheticScopeFunctionStubs.swift` の該当登録と `ScopeFunctionKind` 該当分岐。インライン特例の撤去可否は KSP-INF-007 の実測とセットで判断）
- [ ] KSP-602: run/with/apply を Kotlin 化する（前提: KSP-CAP-008。`apply` は**スタブ未登録・名前特例のみ**で動作中のため宣言を新設。削除対象は同スタブの with/run 登録 + `CallLowerer+ScopeFunctionLowering.swift` の該当分岐）
- [ ] KSP-603: context/contextOf を Kotlin 化する（experimental。同スタブの context×arity1-6 / contextOf 登録。diff: `context`/`contextOf` ケース新規追加）
- [ ] KSP-604: repeat を .kt 化する（`kotlin/Standard.kt`。kk_* ゼロ・Sema 特例は RF-SEMA-002 でメタデータ駆動化済み。`HeaderHelpers+SyntheticStdlibLoopStubs.swift`（93行）削除 + `CallLowerer+StdlibLoops.swift` のインライン展開特例の維持/撤去を実測判断）
- [ ] KSP-605: require/check/error を Kotlin 化する（削除 kk_*: `kk_require`, `kk_require_lazy`, `kk_check`, `kk_check_lazy`, `kk_error`。実装先 `kotlin/Preconditions.kt`。前提確認: `ContractNonNullEffect` の smart-cast 効果を bundled 宣言でも維持できること（不可なら新規 CAP 起票）。注意: `RuntimePreconditions.swift` は TODO()/synchronized と同居 — 巻き込み禁止）
- [ ] KSP-606: requireNotNull/checkNotNull を**新規実装**する（Sema 未登録の欠落 API。孤児 runtime `kk_check_not_null(_lazy)`/`kk_require_not_null(_lazy)` 4件は削除。diff: 新規ケース追加）
- [ ] KSP-607: assert を Kotlin 化する（削除 kk_*: `kk_precondition_assert`, `kk_precondition_assert_lazy`。残留: `__kk_assertions_enabled`（新設）のみ）
- [ ] KSP-608: Pair/Triple クラス本体を Kotlin 化する（削除 kk_* 9: `kk_pair_first/second/to_string/toList` + `kk_triple_first/second/third/to_string/toList`。残留: `__kk_pair_new`/`__kk_triple_new`。実装先 `kotlin/Tuples.kt`）
- [ ] KSP-609: `to` infix を Kotlin 化し name-string 特例を全廃する（前提: KSP-608。特例削除: `CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials.swift` の Any.to 特例 / `+MemberCallInferenceRegularNoCandidateFallbacks.swift` の二重実装 / `CollectionLiteralLoweringPass+CallRewriteFactories.swift` の to→kk_pair_new・Triple ctor 書き換え / `CallLowerer+MemberCallSupport.swift` の "to" エントリ。diff: `to` 単独ケース追加）
- [ ] KSP-610: KotlinVersion を Kotlin 化する（kk_* 9 → 残留 `__kk_kotlin_version_current`（ビルド時定数注入）のみ。着手時に runtime 現在値 (2,3,20) と CLAUDE.md の 2.3.10 の食い違いを確認・是正。diff 新規）
- [ ] KSP-611: Closeable/AutoCloseable/use を Kotlin 化する（実装先 `kotlin/io/Closeable.kt`。残留 `__kk_auto_closeable_create` のみ。use の try-finally インライン特例（`CallLowerer+ScopeFunctionLowering.swift`）は当面維持し、撤去は KSP-601 と同判断）
- [ ] KSP-612: DeepRecursiveFunction を Kotlin 化する（**Sema 特例整理が主眼**: CallTypeChecker 4箇所（うち1組は重複疑い）+ HOFAdapter/ClosureAdapters の2箇所。ブリッジ4関数は全部 `__kk_` 残留 — トランポリンが存在意義。runtime の fatalError 4箇所の catch 可能化は DEBT-RT 系タスクへ。diff 新規）
- [ ] KSP-613: runCatching 残存特例を撤去する（KSP-304 完了後も残る名前特例を通常解決へ。着手時 `rg runCatching Sources/CompilerCore --type swift` で全列挙して固定）

#### io / system

- [ ] KSP-614: print/println を Kotlin 化する（削除 kk_* 4: `kk_println_newline`, `kk_println_any`, `kk_print_noarg`, `kk_print_any` → 残留 `__kk_print_raw` 1本に統合。改行付与・toString は Kotlin 側。特例削除: CallTypeChecker の println 即断 / CollectionLiteralLoweringPass+LookupTables / OperatorLoweringPass / EnumNameAccessLoweringPass — 後2者は挙動保持の代替設計必須。実装先 `kotlin/io/Console.kt`）
- [ ] KSP-615: readLine/readln/readlnOrNull を Kotlin 化する（削除 kk_* 3 → 残留 `__kk_readline_raw`。null 許容/例外分岐は Kotlin 側）
- [ ] KSP-616: TODO() を Kotlin 化する（削除 kk_* 2: `kk_todo`, `kk_todo_noarg`。ブリッジ不要 — NotImplementedError へ委譲。KSP-605 と runtime 同居ファイル注意）
- [ ] KSP-617: exitProcess/getTime 系を `__kk_` 降格する（`kk_system_exitProcess`, `kk_system_getTimeMillis/Micros/Nanos`, `kk_system_currentTimeMillis`, `kk_system_nanoTime`, `kk_system_process_start_nanos` — OS 窓口の改名 + 公開層 .kt 化。**併せて到達不能デッドコード `kk_system_measureTimeMillis/measureTimeMicros/measureNanoTime` 3関数を削除**（`StdlibSpecialCallKind` 優先で構造的に呼ばれない）。diff: getTimeMillis 系追加）
- [ ] KSP-618: synchronized を整理する（`kk_synchronized` → `__kk_synchronized` 降格 + 公開層 Kotlin 化。diff: synchronized ケース新規）
- [ ] KSP-619: kotlin.io 例外を Kotlin 化する（`FileSystemException` 基底を前倒し実装 + `AccessDeniedException`/`FileAlreadyExistsException`。ブリッジ残留ゼロ・特例ゼロ。**併せて BUG-016（RuntimeFileIO が型でなくメッセージ文字列の汎用 Throwable を送出 — 型付き catch 不成立の疑い）を実クラス送出へ修正**。実装先 `kotlin/io/FileSystemException.kt`。diff: 型付き catch ケース新規）

#### collections

- [ ] KSP-620: joinToString/joinTo の List/Array 版を統一する（孤児 `kk_string_joinToString` の正式タスク第1弾。bundled `StringSplitJoin.kt` の `List<T>.joinToString` と合成スタブの二重定義解消 — 前提: KSP-INF-011 のガード漏れ修正。削除 kk_*: `kk_list_joinToString`, `kk_array_joinToString`。残留 `__kk_string_joinToString`。**併せて呼び出し元ゼロの `CallLowerer+CollectionStdlibMemberCalls.swift` をファイルごと削除**）
- [ ] KSP-621: joinToString/joinTo の Iterable/Sequence 版を統一する（前提: KSP-620。削除 kk_* 4: `kk_iterable_joinTo`, `kk_iterable_joinToString`, `kk_sequence_joinTo`, `kk_sequence_joinToString` + `CallLowerer+UnresolvedMemberCalls.swift` の収束特例。diff: Iterable 版・joinTo 単独ケース追加）
- [ ] KSP-622: buildList を Kotlin 化する（前提: KSP-CAP-008。下敷き: 死蔵 `Stdlib/kotlin/collections/CollectionBuilders.kt` 実装済み。削除 kk_*: `kk_builder_list_add`, `kk_builder_list_addAll` → 残留 `__kk_build_list(_with_capacity)`。特例: `CollectionLiteralLoweringPass+CallRewriteFactories.swift` の build* 書き換え該当分岐）
- [ ] KSP-623: buildSet/buildMap を Kotlin 化する（前提: KSP-622。削除 kk_*: `kk_builder_set_add`, `kk_builder_set_addAll`, `kk_builder_map_put` → 残留 `__kk_build_set`/`__kk_build_map`）
- [ ] KSP-624: buildString を Kotlin 化する（前提: KSP-622, KSP-311。`builderDSLKind`（`CallTypeChecker+BuilderDSL.swift`）の該当分岐 + `CallLowerer.swift` の append 引数ボクシング特例撤去。`kk_build_string` 系 4 → `__kk_` 降格 or StringBuilder 経由化）
- [ ] KSP-625: ArrayDeque を Kotlin 化する（削除 kk_*: `kk_arraydeque_first/last/isEmpty/toString` は Kotlin 化、`kk_arraydeque_new/addFirst/addLast/removeFirst/removeLast/size` + get は `__kk_arraydeque_*` 最小残留（リングバッファ直変異）。特例: `isArrayDequeLikeType`（CallLowerer+ReceiverTypePredicates）ほか4箇所。実装先 `collections/ArrayDeque.kt`）
- [ ] KSP-626: IndexedValue/forEachIndexed を Kotlin 化する（IndexedValue を data class 化（現状 `kk_pair_first/second` 流用）+ `kk_list_forEachIndexed`/`kk_list_withIndex` 削除。diff: forEachIndexed/withIndex ケース追加）
- [ ] KSP-627: コレクション typealias を .kt 化する（`ArrayList`/`HashSet`/`HashMap`/`LinkedHashMap` typealias 4 + `LinkedHashSet` 具象クラス。**typealias のパーサ/Sema 対応は確認済み** — `HeaderHelpers+SyntheticCollectionTypeAliases.swift`（272行）を宣言数行に置換する最小工数タスク。残留ゼロ（LinkedHashSet ctor は `__kk_emptySet`/`__kk_iterable_toMutableSet` 流用））
- [ ] KSP-628: List→配列変換（object+signed 9）を Kotlin 化する（`toTypedArray`/`toCharArray`/`toBooleanArray`/`toShortArray`/`toDoubleArray`/`toFloatArray`/`toIntArray`/`toLongArray`/`toByteArray` = `kk_list_to*Array` 9 削除 → 残留は各配列型のアロケーションコアのみ。特例: `unresolvedCollectionMemberNames` ほか）
- [ ] KSP-629: List→配列変換（unsigned 4）を Kotlin 化する（前提: KSP-628。`kk_list_toUByteArray/toUShortArray/toUIntArray/toULongArray` 削除）
- [ ] KSP-630: Iterator.forEach/withIndex を**新規実装**する（実装も計画も無かった真空地帯。参照実装: `kk_list_forEach`（RuntimeCollectionHOF）/ IndexedValue。実装先 `collections/Iterators.kt`。diff 新規）
- [ ] KSP-631: Iterator.asSequence を**新規実装**する（前提: KSP-CAP-001/002 + KSP-441。参照: `kk_iterable_asSequence`）
- [ ] KSP-632: IterableRegistry 残余の HOF を Kotlin 化する（KSP-435 対象外の登録分: `reduceRight(Indexed)`/`sumBy(Double)`/`plusElement`/`minusElement`/`minus`。着手時 `rg 'registerIterable' Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticIterableRegistry.swift` で固定）
- [ ] KSP-633: IterableRegistry の殻を .kt 化する（`MutableIterable`/`AbstractCollection`/`AbstractMutableCollection` interface/abstract class 宣言）
- [ ] KSP-634: maxWith/minWith を KSP-461 の明示対象に追記する（現状 rg パターン包含の推定のみ — KSP-461 のタスク文へ明示列挙を追加する編集タスク）

#### math / numbers

- [ ] KSP-635: kotlin.math の純ロジック群を Kotlin 化する（abs/sign/min/max + PI/E 定数 — **名前特例ゼロで最もクリーンな移行対象**。実装先 `kotlin/math/Math.kt` 新設。対象 kk_*: `kk_math_abs*` 4 / `kk_math_sign*` 4 / `kk_math_min*`・`kk_math_max*` 各6 / `kk_math_PI`/`kk_math_E`。diff は math_* 15ケース既存）
- [ ] KSP-636: kotlin.math の丸め系を Kotlin 化する（ceil/floor/round/truncate/withSign — Foundation 依存の有無を着手時確認し、純ロジック化できない分のみ `__kk_` 降格。対象 kk_* 約12）
- [ ] KSP-637: kotlin.math の超越関数を `__kk_math_*` 降格する（sin/cos/tan/asin/acos/atan/atan2/exp/expm1/ln/ln1p/log/log2/log10/sinh/cosh/tanh/acosh/asinh/atanh/cbrt/hypot/pow/sqrt/IEEErem/nextTowards の Double/Float 版 — libm 窓口の改名 + 公開層 .kt 化。約52 kk_*。`rg -o '@_cdecl\("kk_math_[a-zA-Z0-9_]*"\)' Sources/Runtime` で着手時固定）
- [ ] KSP-638: roundToInt/roundToLong/ulp/nextUp/nextDown を整理する（**`HeaderHelpers+SyntheticMathStubs.swift` と `+SyntheticCoercionStubs.swift` の二重登録を一本化**した上で `__kk_` 降格。kk_* 10）
- [ ] KSP-639: coerce の Int/Long/Double/Float を本物の Kotlin 実装にする（**`ranges/RangeCoercion.kt` の `= this` フェイク12関数を実装で置換**。3並列 KIR 特例（`CallLowerer+PrimitiveMemberCalls.swift` / `+SafeMemberCalls.swift` / `+LegacyMemberLikeCalls.swift` の coerce 分岐）+ Sema 特例（`CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials.swift` — コメントの Byte/Short 記載とコードの乖離も解消）を撤去。runtime `RuntimeNumericBitManip.swift` の coerce 24関数削除。残留ゼロ見込み）
- [ ] KSP-640: coerce の unsigned 4型を Kotlin 化する（前提: KSP-639。スタブ残存の `kk_ubyte/ushort/uint/ulong_coerceIn/coerceAtLeast/coerceAtMost` 12 + range 版 `kk_int/long_coerceIn` 2 を削除）
- [ ] KSP-641: coerce の Comparable 総称版・ClosedFloatingPointRange range 版を**新規実装**する（本家 API `T.coerceIn(min?, max?)` / `coerceIn(ClosedFloatingPointRange)` が現状全く存在しない。前提: KSP-639, KSP-652）
- [ ] KSP-642: rotateLeft/rotateRight を Kotlin 化する（Int/Long 版 kk_* 4 削除。shl/shr/or で完結・残留ゼロ。diff: rotate ケース新規）
- [ ] KSP-643: countOneBits/countLeadingZeroBits/countTrailingZeroBits を Kotlin 化する（**BUG-015 修正込み: Long 版は Sema 通過後に KIR で握りつぶされる壊れたパス** — Kotlin 実装で Int/Long 両対応に。Int 版 kk_* 3 削除。diff: count 系新規）
- [ ] KSP-644: takeHighestOneBit/takeLowestOneBit/highestOneBit/lowestOneBit を Kotlin 化する（Int/Long 版 kk_* 8 削除・残留ゼロ）
- [ ] KSP-645: kotlin.experimental の Byte/Short 版 and/or/xor/inv を**新規実装**する（本家仕様は Byte/Short 用。現行の Int 版登録（`HeaderHelpers+SyntheticExperimentalBitwiseStubs.swift`）は汎用 Int/Long 特例が先に解決する完全デッドコードのため削除 — CLEANUP-STUB-101 と重複しない側で実施）
- [ ] KSP-646: isNaN/isFinite/isInfinite を Kotlin 化する（IEEE754 ビットパターン判定。kk_* 6 削除。diff: isNaN/isFinite ケース新規 — 現状カバレッジ薄）
- [ ] KSP-647: toBits/toRawBits/fromBits を `__kk_` 降格する（ビットパターン変換窓口。kk_* 6 + fromBits トップレベル登録。nextTowards は KSP-637 側）

#### time / sequences / ranges

- [ ] KSP-648: TimeMark/ComparableTimeMark を Kotlin 化する（削除 kk_*: `kk_time_mark_elapsed_now/has_passed_now/has_not_passed_now/plus_duration/minus_duration/minus_mark/compare` 7 — Duration 演算主体。実装先 `kotlin/time/TimeMark.kt`。diff 新規）
- [ ] KSP-649: TimeSource/Monotonic を Kotlin 化し ValueTimeMark を**新規実装**する（残留: `__kk_time_source_mark_now`/`__kk_time_source_monotonic_mark_now`/`__kk_time_source_as_clock`（単調クロック読み）。**本家 `TimeSource.Monotonic.ValueTimeMark`（value class）はリポジトリに存在しない — 新規追加**。前提: value class 対応の確認 + KSP-648）
- [ ] KSP-650: TestTimeSource/AbstractLongTimeSource/AbstractDoubleTimeSource を Kotlin 化する（削除 kk_*: `kk_test_time_source_new/plus_assign/mark_now/read` 4。前提: KSP-648）
- [ ] KSP-651: SequenceFactories を移設する（死蔵 `Stdlib/kotlin/sequences/SequenceFactories.kt`（112行・sequence{} ビルダー込み・完成度高）を bundled ツリーへ。kk_*: `kk_sequence_of`/`kk_empty_sequence`/`kk_sequence_generate(_noarg)` 4 → `__kk_` 降格 + Sema 未登録の孤立 `kk_sequence_of_single` の生死判定。特例: CallTypeChecker 6箇所（二重実装疑い含む）+ CollectionLiteralLoweringPass 3箇所 + `CallLowerer.swift` の generateSequence ハードコード撤去。前提: KSP-CAP-001（sequence{} 部分）。KSP-441 と同時か直後）
- [ ] KSP-652: ClosedRange<T>/ClosedFloatingPointRange/OpenEndRange の interface を .kt 化する（`HeaderHelpers+SyntheticRangeInterfaceStubs.swift`（382行）+ `+SyntheticRangeProgressionStubs.swift` の OpenEndRange 登録。kk_* ゼロ・残留ゼロの純宣言。具象 IntRange 等の conformance 配線は KSP-451 と同一 PR か後続で調整）

#### 例外・言語コア表面（(c) 再監査 2026-07-10 で b-reclass 確定分）

- [ ] KSP-653: Throwable 本体とコンストラクタ群を Kotlin 化する（クラス階層宣言 + 0/1/2引数 ctor。残留: `__kk_throwable_new(_with_cause)`（GC 確保の1行ブリッジ）。注意: `kk_is_cancellation_exception` は coroutine 側 (c) で対象外）
- [ ] KSP-654: Throwable メンバを Kotlin 化する（message/cause getter・initCause・addSuppressed/getSuppressed/suppressedExceptions。前提: KSP-653。残留: `__kk_throwable_setCause`/`__kk_throwable_appendSuppressed`/`__kk_throwable_suppressedRaw`）
- [ ] KSP-655: stackTraceToString/printStackTrace を Kotlin 化する（前提: KSP-654 + runtime の renderedMessage を「生フレーム取得（`__kk_throwable_rawStackFrames` 新設）」と「整形（Kotlin 側で cause/suppressed チェーンを辿る）」に分離するリファクタ）
- [ ] KSP-656: 例外サブクラス階層の宣言を .kt 化する（IllegalArgumentException 等 `registerSyntheticExceptionConstructor` ループの置換。前提: KSP-653）
- [ ] KSP-657: Array ファクトリ系を Kotlin 化する（`HeaderHelpers+SyntheticArrayStubs.swift`（(c) 一括計上だった 2043 行）内の b-reclass 第1弾。着手時に factory 群を rg で固定）
- [ ] KSP-658: Array contentEquals/contentToString/copyOf/copyOfRange を Kotlin 化する
- [ ] KSP-659: Array sorted*/binarySearch を Kotlin 化する（比較コアは KSP-309 の Comparator Kotlin 実装を利用）
- [ ] KSP-660: Array 符号なしビュー変換を Kotlin 化する（**併せて BUG-019（ByteArray.joinToString/contentEquals 未スタブ）を吸収**。`kotlin.jvm.isArrayOf` は CLEANUP-STUB-098 側で削除）
- [ ] KSP-661: Char 判定系を Kotlin 化する（isDigit/isLetter/isLetterOrDigit/isWhitespace/isUpperCase/isLowerCase 等。残留: `__kk_char_unicode_category` 等テーブル参照ブリッジ新設）
- [ ] KSP-662: Char 変換系を Kotlin 化する（uppercaseChar/lowercaseChar/titlecase/digitToInt(OrNull)/digitToChar。ロケール依存 2 関数は `__kk_*_locale` ブリッジ残留（`java.util.Locale` interop 自体は (a) 削除方針）。前提: KSP-661）
- [ ] KSP-663: Char サロゲート演算を Kotlin 化する（isSurrogate 系/code 変換。前提: KSP-661）
- [ ] KSP-664: AbstractIterator + プリミティブ Iterator 殻を .kt 化する（本家同型の純 Kotlin・ブリッジゼロ。`HeaderHelpers+SyntheticIteratorStubs.swift`（272行）削除）
- [ ] KSP-665: `HeaderHelpers+SyntheticStringTypeHelpers.swift`（299行）を撤去する（Sequence/Iterable/Collection/List の型シェル取得ヘルパー — interface の .kt 化で自然不要化。`+SyntheticIterableRegistry.swift` との並行実装解消）
- [ ] KSP-666: 注釈を .kt 化する（第1弾: kotlin 直下の共通 opt-in マーカー — ExperimentalUnsignedTypes/ExperimentalMultiplatform/ExperimentalSubclassOptIn 等 + uuid/encoding/reflect の Experimental マーカー。コンパイラの FQName 認識は宣言出自と無関係のため移設可能 — golden `native_annotations.kt` の実使用パターンで検証）
- [ ] KSP-667: 注釈を .kt 化する（第2弾: kotlin.native + ObjC 系 — ObjCName/CName/HiddenFromObjC/ShouldRefineInSwift/FreezingIsDeprecated 等 15種）
- [ ] KSP-668: 注釈を .kt 化する（第3弾: kotlin.experimental 系 + `HeaderHelpers+SyntheticMetaprogAnnotationHelpers.swift` の b-reclass 分。JVM 固有注釈は (a) 分割してから）
- [ ] KSP-669: Comparable/RandomAccess の interface 宣言を .kt 化する（`HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` の自己登録分のみ。プリミティブ型への Comparable 適合付与は c-hard 残留。死コード `compareToOrNull` は CLEANUP-STUB-098 側）

#### concurrent / coroutines（(c) 再監査 2026-07-10 の b-reclass 分。全 Atomic タスク共通注意: kk_atomic_* はスタブ側 prefix 補間 emit のため rg 完了チェックは補間を考慮）

- [ ] KSP-670: AtomicBoolean を Kotlin 委譲化する（`AtomicMigration.kt` の委譲パターンで get/set/getAndSet 等 — CAS ループ非依存分のみ。`kk_atomic_bool_*` のうち load/store/exchange はブリッジ残留）
- [ ] KSP-671: Atomic reverse 変種と compareAndSet 公開層を Kotlin 化する（fetchAndAdd/fetchAndIncrement/fetchAndDecrement + compareAndSet/compareAndExchange の公開層委譲。CPU 命令コアはブリッジ残留。前提: KSP-670 でパターン確立）
- [ ] KSP-672: Atomic 配列 *At 系の委譲分を Kotlin 化する（loadAt/storeAt 等の公開層 + 境界検査を Kotlin 側へ。コア CAS 命令はブリッジ残留。39関数中の委譲可能分を着手時固定）
- [ ] KSP-673: Atomic CAS ループ系 13 関数を Kotlin 化する（getAndUpdate/updateAndGet/fetchAndUpdate + 配列版 fetchAndUpdateAt/updateAt/updateAndFetchAt。前提: **KSP-CAP-004**（`AtomicMigration.kt` コメントの保留解除））
- [ ] KSP-674: Flow ビルダーを Kotlin 化する（`kk_flow_as_flow`/`kk_flow_empty`/`kk_flow_of` — (c) ブリッジ `kk_flow_create`+`kk_flow_emit` の合成で表現。前提: **KSP-CAP-010** + KSP-CAP-012）
- [ ] KSP-675: SharedFlow を Kotlin 化する（`kk_mutable_shared_flow_create/emit/try_emit`, `kk_shared_flow_collect/replay_cache` — replay buffer・購読者管理は Kotlin の状態遷移で表現可（2026-07-10 再監査で b-reclass 確定）。前提: KSP-674）
- [ ] KSP-676: StateFlow と share_in/state_in を Kotlin 化する（`kk_mutable_state_flow_create/emit/try_emit`, `kk_state_flow_value`, `kk_flow_share_in/state_in/release/retain`。前提: KSP-675。c-hard 残留: `kk_flow_stopped`/`kk_flow_emit_with_timestamp`）
- [ ] KSP-677: Mutex/Semaphore の (b) 分 9 関数を Kotlin 化する（withLock 等ラッパー層。カーネル同期コア 6 関数は c-soft 残留 — 分離仕様は `docs/stdlib-pipeline.md` §9 の再監査記録に従う）
- [ ] KSP-678: Channel の (b) 分 7 関数を Kotlin 化する（iterator 層等。suspension コア 3 関数は c-soft 残留）
- [ ] KSP-679: coroutineScope/supervisorScope の公開ラッパー 4 を Kotlin 化する（内部プリミティブ `kk_coroutine_scope_*`/`kk_supervisor_scope_*` は (c) のまま委譲。前提: KSP-CAP-012）

#### delegates / reflect

- [ ] KSP-680: delegate インターフェース群を .kt 化する（ReadOnlyProperty/ReadWriteProperty/PropertyDelegateProvider。前提: KSP-CAP-007）
- [ ] KSP-681: ObservableProperty/Delegates 残余を Kotlin 化する（KSP-491 の範囲を超える残り約20系統。前提: KSP-491, KSP-680）。BUG-017はKSP-CAP-013のPR #4976で独立に修正済みのため本タスクの前提から外れた
- [ ] KSP-682: KProperty0/1/2・KMutableProperty0/1 の殻を .kt 化する（前提: **KSP-CAP-009**（supertype 位置の関数型リテラル）。c-soft 解除。**併せて BUG-018（`kotlin.reflect.full.createInstance` が宣言のみでリンクエラー確定）の削除 or 実装を判断**）

### CLEANUP-STUB 追補（(a) 削除。2026-07-10 監査。採番は履歴最終 095 の続き。手順は RF-STUB-002 レシピ）

> 「本家で deprecated/obsolete かつ KSwiftK でも未実装」の二重死と fiction。**W6 の移行より先に実施を推奨**（移行対象面積が減る）。

- [ ] CLEANUP-STUB-096: kotlin.native.concurrent のレガシー群を削除する（`HeaderHelpers+SyntheticNativeConcurrentRegistry.swift` の約59%: Legacy AtomicInt/AtomicLong/AtomicNativePtr, FreezableAtomicReference 公開層, kotlin.native.concurrent.AtomicReference, MutableData, DetachedObjectGraph, WorkerBoundReference, atomicLazy, ObsoleteWorkersApi 系 3, ensureNeverFrozen, freeze/isFrozen 公開層。内部 `kk_freeze_object`/`kk_is_frozen` は TransferMode 用に残留）
- [ ] CLEANUP-STUB-097: NativeDataStubs のレガシー群を削除する（`HeaderHelpers+SyntheticNativeDataStubs.swift` の約69%: BitSet（`@ObsoleteNativeApi`+未実装・325行）/ ImmutableBlob（ERROR-deprecated+未実装・169行）/ Vector128+vectorOf（同・74行））
- [ ] CLEANUP-STUB-098: Function 型の fiction ほかを削除する（`Function1.andThen`/`Function1.compose`/`Function2.curried` — 本家に存在しない Java 由来誤移植・参照ゼロ（`HeaderHelpers+SyntheticFunctionTypeStubs.swift` + `RuntimeFunctionTypes.swift`）+ `compareToOrNull`（ブリッジ未設定の死コード）+ `kotlin.jvm.isArrayOf`）
- [ ] CLEANUP-STUB-099: JS/Wasm 専用 opt-in マーカー6種を削除する（ExperimentalJsCollectionsApi/ExperimentalJsExport/ExperimentalJsReflectionCreateInstance/ExperimentalJsStatic/ExperimentalWasmJsInterop + ExperimentalWasmInterop — `HeaderHelpers+SyntheticExperimentalMarkerStubs.swift` 内）
- [ ] CLEANUP-STUB-100: Atomic の Java interop fiction を削除する（恒等関数の `kk_atomic_int/long/bool/ref_asJavaAtomic` 4 + `kk_atomic_int/long/ref_array_asJavaAtomicArray` 3 + `kk_java_atomic_long_array_asKotlinAtomicArray` + 未使用重複 `kk_reentrant_read_write_lock_new`）
- [ ] CLEANUP-STUB-101: 監査で確定したデッドコードを一括削除する（`kk_math_round_mode` 系15（Sema 登録ゼロ・到達不能）/ `kotlin.experimental` Int 版登録一式（汎用特例が先に解決）/ `kk_check_not_null(_lazy)`/`kk_require_not_null(_lazy)` 4 / CLEANUP-STUB-084 取り残しの `registerSyntheticJvmAnnotationClass`・`registerSyntheticBooleanAnnotationPropertyAndConstructor` 2関数 / `kk_sequence_of_single` の生死判定。※`kk_system_measureTime*` 3 と `CallLowerer+CollectionStdlibMemberCalls.swift` は KSP-617/620 と重複するため先行した方で実施）
- [ ] CLEANUP-STUB-102: cinterop 未配線外殻を削除する（`HeaderHelpers+SyntheticCInteropStubs.swift` 3,065行中、実働12関数（ポインタ⇔Long 変換・pin/unpin・配列⇄CValues・文字列変換 — `__kk_` 降格で残留）以外の alloc/nativeHeap/Arena/MemScope/StableRef/CPointer.get/set/pointed/value/reinterpret/Vector128 アクセサ等、externalLinkName 未設定で「コンパイルは通るが動かない」外殻を削除。必要になったら本家 .def ベースで再実装する方針（2026-07-10 決定）。`+SyntheticNativeInteropHelpers.swift`（1292行）の get/set/pointed 系ビルダーも道連れ削除）
- [ ] CLEANUP-STUB-103: 削除タスク未起票の (a) 21 ファイルを再起票する（CLEANUP-STUB 個別リスト消失で追跡ゼロだったもの: BigInteger / Concurrency / Dynamic / FileIO / FileTreeWalk / FileWalkDirection / FilesUtility / JsFunction / LocaleConstructor / NativeFunctionAnnotation / OnErrorAction / PathStubs 本体+分割3 / PlatformObjectHelpers / ReadWriteLock / Serialization / Test / URI / URL。本タスクで対象表を確定し、以後1ファイル=1タスク（CLEANUP-STUB-104〜）で消化する）

### バグバックログ（BUG-NNN。既存・未修正バグの追跡。PR 状態は各タスクの記載時点）

> このセクションは既存の未修正バグと、同じPR内で安全に修正できなかったバグの追跡用。新たに発見した修正可能なバグは、最小再現と回帰テストを含めて発見したPR内で修正し、報告だけのためにここへ追加しない。

- [ ] BUG-017: 当初の診断は不正確だった。実際に調査すると `lazy()`/`lazy(mode)`/`lazyOf` の戻り値型登録は元から正しく `kotlin.Lazy` を指しており、真因は (1) 呼び出し側の型注釈 `Lazy<Int>` の解決（`resolveTypeRef`）がスコープ／import優先順位を無視し `kotlin.properties.Lazy` に誤って解決していたこと（KSP-CAP-013で修正）と (2) `lazy(mode) { }` の2引数オーバーロードが `lazyModeSymbol` の旧fqNameに起因してデフォルトimportスコープから到達不能だったこと、の2点。KSP-681を待たずKSP-CAP-013のPR #4976で修正済み（マージ後に`[x]`化する）
- [ ] BUG-036: `kotlin.text.CASE_INSENSITIVE_ORDER` 等の合成 top-level プロパティが、モジュール初期化時にキャッシュされるはずの global を読まず、参照のたびに `kk_string_case_insensitive_order()` を再実行して新規インスタンスを生成する（`--emit kir` で使用箇所ごとに独立した `call` が発行され、cached global への `loadGlobal` が起きないことを確認済み。値としては動作するが参照同一性が崩れる: `val a = CASE_INSENSITIVE_ORDER; val b = CASE_INSENSITIVE_ORDER` は同一インスタンスになるべき）— PR #4835 で発見。testKotlinTextCaseInsensitiveOrderEdgeCases の itable dispatch 障害報告の再現調査中に判明（**当該パニック自体は現行 HEAD `981b96169c` では再現せず**: `--emit kir` 上 dispatch=itable[0:0] がランタイム登録と一致、`swift_test.sh` で4回連続 pass 確認済み。原因は調査当時の Xcode ツールチェイン不一致の疑い — 本件はその副産物として見つかった別問題）
- [ ] BUG-037: interface 型オペランド同士の `===`/`!==` が Sema 型チェックを通らず `KSWIFTK-TYPE-0001: Type constraint could not be satisfied` になる（具象クラスが実装した interface 型の変数同士でも再現。最小再現: `interface Foo { fun bar(): Int }` `class FooImpl : Foo { override fun bar() = 1 }` `fun main() { val a: Foo = FooImpl(); val b: Foo = a; val same: Boolean = (a === b) }`）— PR #4835 で発見。BUG-020 の再現性検証中に偶然発見
- [ ] BUG-038: PR #4636 の CI で判明した runtime 表示/例外 message の不整合。`kk_println_any(kk_box_char(0xDF1F))` と `println("hello🌟".lastOrNull())` が `?` ではなく U+FFFD を出力し、`(42 as String)` の `ClassCastException.message` が空になる — 再現: `Tests/RuntimeTests/RuntimePrintlnTests.swift`、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+StringHOFEdgeCases.swift`、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+InlineFunctionExceptionPropagation.swift`。修正 PR: #4636（マージ後に `[x]` 化）
- [ ] BUG-137: 初期化子付き top-level `var` の custom getter 読み出しが getter を経由せず property global を直接読む（最小再現: `Scripts/diff_cases/top_level_backing_field.kt`、発見元: PR #4684 の CI）。修正: PR #4684
- [ ] BUG-138: クラスメンバの custom accessor が暗黙 receiver の setter dispatch と backing-field のインスタンス storage を迂回する（`implicit_receiver_setter_assign.kt` は setter が bypass され `10/1012` ではなく `5/4`、`custom_getter_field_access.kt` は getter 内 `field` と class-body initializer が global 経路になり `10/105/205/305` ではなく `10/5/5/5`）。最小再現: `Scripts/diff_cases/implicit_receiver_setter_assign.kt` / `Scripts/diff_cases/custom_getter_field_access.kt`。発見元: PR #4680 CI 修理。修正: PR #4680（未マージ）
- [ ] BUG-039: master CI（`Full Swift Tests (RuntimeTests)` ジョブ）が2026-07-15〜16に直近4回中3回失敗。原因は BUG-021/023/024/028 系と同根で、`kk_runtime_force_reset()` 等が書き換える `Sources/Runtime/RuntimeGC.swift` のプロセス全体共有ハンドルテーブル（`runtimeStorage.objectPointers` 等）に対し、XCTest 時代の `RuntimeTestIsolationSupport.swift`（`gcSemaphore` 等のプロセス全体セマフォ、`IsolatedRuntimeXCTestCase.setUp/tearDown` 経由）が提供していたクロスファイル排他が、Swift Testing の `@Suite` では構造的に再現できない（`XCTestCase` サブクラス専用の仕組みで Swift Testing の struct suite からは使えない）。`@Suite(.serialized)` はスイート内のみを直列化し、他ファイルの並行スイートとは排他されないため、あるスイートの reset が別スイートの生存中ハンドルを消し飛ばし、`invalid range/array/string handle` パニックや `Set`/`Array` 内容破損（解放先アドレスの再利用によるものと推定）を引き起こす。対象確認: `Tests/RuntimeTests/RuntimeSynchronizedTests.swift`（PR #4823 で移行済み・`init()` と各 `@Test` の `defer` で `kk_runtime_force_reset()` を正しく呼び `.serialized` も付与済みだが、cross-suite 排他が無いため依然として攻撃源になり得ることを示す新規ケース。BUG-020〜035 では未記載）。既存の BUG-023/024/028 も現行 master 上で確認済みの同根の実攻撃源（詳細は各項目参照）。最小再現: `DEVELOPER_DIR=/Applications/Xcode-beta.app SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh --filter '^RuntimeTests\.' -Xswiftc -swift-version -Xswiftc 6` をローカルで数回実行（`SWIFT_TEST_PARALLEL` 未設定＝デフォルト `--parallel --num-workers 4`）。発見元: 本 master CI 失敗調査タスク（2026-07-16）。暫定対応: `.github/workflows/ci.yml` の `full-swift-tests` ジョブで `RuntimeTests` マトリクスエントリのみ `SWIFT_TEST_PARALLEL: "0"` を設定し直列実行に固定（実測 196 tests / 0.235 秒、タイムアウト無関係）。根本対応基盤として、既存のプロセス全体セマフォを Swift Testing の各 test case に適用する `RuntimeIsolationTrait` を PR #4908 で追加し、対象ファイルの段階移行を開始。暫定緩和 PR: #4846 → **この緩和が BUG-040 を誘発した（`--no-parallel` 化で exec() 引数長制限に抵触）**

- [ ] BUG-040: BUG-039 の暫定緩和 PR #4846（`RuntimeTests` マトリクスエントリに `SWIFT_TEST_PARALLEL: "0"` を設定）が master CI に新規リグレッションを誘発。`swift test --no-parallel --filter '^RuntimeTests\.'` は `--parallel` 時と異なりマッチした全 XCTest ID（RuntimeTests は ABIMismatchTests 等を含め約3000件超）を **1つの exec() 引数** として `KSwiftKPackageTests.xctest` に直接渡す経路を通るため、Linux の per-argument exec() 制限（`MAX_ARG_STRLEN` ≈128KB）を超え `error: posix_spawn error: Argument list too long (7)` でテスト実行前に落ちる。Swift Testing 側のテスト（196件）はこのエラーの後に正常に走り切って `passed` と表示されるため、ログ末尾だけを見ると成功に見えるが、ジョブ全体の exit code は 1 のまま。macOS では `ARG_MAX` が大きく再現しないため、`--no-parallel` はローカル green でも Linux CI で落ちうる（PR #4846 バリデーションはこの経路を踏んでいなかった）。再現: master commit `a28cd1cf13`（PR #4846 マージ後）以降の全 `Full Swift Tests (RuntimeTests)` run（例: Actions run 29479751122 / 29416122834 / 29405211032）。発見元: 本 master CI 失敗調査タスク（2026-07-17）。対応: `RuntimeTests` を独立ジョブ `full-swift-tests-runtime` に切り出し、`Scripts/shard_swift_tests.sh` の `--mode static`（ソースから suite/class 名を抽出し `--target-prefix\.(Type1|Type2|...)(/|$)` を 50 件ずつチャンク化）経由で実行するよう変更、`SWIFT_TEST_PARALLEL=0` は維持。`shard_swift_tests.sh` 側の `shard_count <= 1` 早期リターン（チャンク化をバイパスして生の `--filter` を投げていた）も削除し、単一シャード実行でも常にチャンク化されるようにした。ローカルでチャンク生成をドライラン確認済み（187 suite/class → 50件ずつ4チャンク、各チャンクのフィルタ長は数KB程度で制限を十分下回る）
- [ ] BUG-041: `launch { }` の子コルーチン本体が、直後（介在する suspension point なし）の同期的な `cancelJob.cancel()` より先に実行を開始してしまうことがある、`kk_kxmini_launch`（`Sources/Runtime/RuntimeCoroutine.swift`）の起動-キャンセル競合。原因: `KxMiniRuntime.launch(workItem:)` が `DispatchQueue.global()`（真の並行スレッドプール）へ即座に dispatch するため、子スレッド側 `job.markStarted()` と親スレッド側 `job.cancel()` の `NSLock` 獲得順序に確定的な happens-before 保証がない。本家 kotlinx.coroutines は `runBlocking` 直下の `launch` を単一スレッドの協調的 event loop で動かすため、suspension point を跨がない `cancel()` は子の実行開始を確実に防げるが、本実装は実スレッド並行に依存しており、子スレッドが `markStarted()`→`cancellationSnapshot()` チェックを親の `cancel()` より先に通過すると本体が走り出し、`delay()` 到達後に協調的キャンセルで中断されて期待外の出力（例: catch節の "cancelled"）が漏れる。再現: `Scripts/diff_cases/coroutine_cancellation_edge_cases.kt` / `Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+CoroutineCancellationEdgeCases.swift` の `testCodegenCompilesCoroutineCancellationEdgeCases`（PR #4830 で追加）。CI高負荷時に発現（本件は PR #4578 の `CompilerBackendTests shard 3/6`、`Actions run 29439186351/job 87460299566` で観測）。頻度は未確定 — ローカルでの繰り返し再現を試みたが、本開発機で他セッションの並行ビルドが多数走っていたことによるリソース競合とみられる無関係な `LinkPhase.swift:109` の `"outputUnavailable"` エラーに阻まれ、対象のレース自体をクリーンに再現できなかった（1回だけ `cancelJob.join()` 待ちとみられる無限待機/0%CPU sleepingも観測したが、上記のリソース競合下での観測のため本バグと確定できない）。低負荷環境での再現率は改めて要検証。同種バグは別セッションでも独立発見・BUG-039 として記録されていたが（`Log coroutine cancel-before-start timing race as BUG-039`, commit `1f925b36d4`）、その後 master 側で BUG-039/040 が全く別内容（RuntimeTests CI の cross-suite GC race / exec引数長制限）で確定したため番号が競合し、本項目として BUG-041 に採番し直した。発見元: PR #4578 の CI 診断中（#4830 自体の変更ではなく `kk_kxmini_launch` の既存 dispatch モデルに起因する既存バグ）
- [ ] BUG-042: ローカル環境（`DEVELOPER_DIR=/Applications/Xcode-beta.app` のツールチェイン）で `swift build --target Runtime --scratch-path .runtime-build/...`（`CodegenRuntimeSupport+RuntimeObjects.swift` の `buildRuntimeObjects`）が per-file `.swift.o` を格納する `Runtime.build/` ディレクトリではなく単一の WMO 統合 `Runtime.o` を生成する。`discoverScratchRuntimeObjectPaths` は `Runtime.build` ディレクトリ名固定探索のみで単一 `.o` へのフォールバックが無いため、ランタイムオブジェクトを発見できず `KSWIFTK-LINK-0001: Unable to locate packaged runtime object files under .../debug/Runtime.build` でリンク失敗する。最小再現: `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt`（任意のケースで再現）、および `swift test --filter testLLVMBackendCanLinkAndRunExecutable`（実行ファイルを実際にリンクする唯一の統合テスト、`LinkPhase.swift:109` で `outputUnavailable` 発生）。フロントエンド/KIR 止まりのテスト（SmokeTests 等）はリンク経路を通らないため影響を受けない — PR #4572 のコンフリクト解消作業（`claude/pr-4572-conflict-f4f7ec`）中、`diff_kotlinc.sh` によるマージ後検証で発見。`CodegenRuntimeSupport+RuntimeObjects.swift`/`LinkPhase.swift` は当該マージで一切変更されておらず、同一 HEAD で `swift build` 本体および StringBuilder/vararg boxing/Golden(Sema+Diagnostics) の500件超のテストは green のため、コード側の回帰ではなくローカルツールチェインの成果物レイアウト差異（WMO）に起因する可能性が高い。BUG-036 の「調査当時の Xcode ツールチェイン不一致の疑い」と同系統の環境要因の可能性あり。上記 BUG-041 の「本開発機で他セッションの並行ビルドが多数走っていたことによるリソース競合とみられる `LinkPhase.swift:109` の `outputUnavailable`」もこの同一事象の可能性が高い
- [ ] BUG-043: PR #4572（StringBuilder source 移行）で `buildString { … }` / `buildStringBuilder { … }` ラムダ内の StringBuilder メンバ呼び出しのうち、`append`/`appendLine`/`insert`/`delete`/`length`/`appendRange` の6種のみ `CollectionLiteralLoweringPass+CallRewriteFactories.swift:636-649` でグローバル builder state（`RuntimeBuilderDSL.swift` の `runtimeBuilderState`）向けに書き換えられ、`reverse`/`clear`/`toString`/`deleteAt`/`deleteCharAt`/`setCharAt`/`set`/`get`/`capacity`/`ensureCapacity`/`trimToSize`/`setRange`/`insertRange`/`replace`/`deleteRange` は書き換え対象外。書き換えられなかった呼び出しは source-backed `StringBuilder.kt` の通常メソッドへフォールバックするが、`runtimeExecuteStringBuilderAction`（`RuntimeBuilderDSL.swift:345-347`）はラムダの暗黙レシーバとして常に `0`（ダミー値）を渡すため、`this` が無効なハンドル `0` になり実行時に壊れる（最小再現: `buildString { append("x"); reverse() }`）。修正には `RuntimeBuilderState`（`RuntimeBuilderDSL.swift:32-`）へ上記14メソッド相当のグローバル状態版プリミティブを追加し `@_cdecl` エクスポート・`RuntimeABISpec` 登録・書き換えリスト拡張が必要で、単純なバグ修正の範囲を超える新規ランタイム面。BUG-042（ローカル環境でのフルリンク不可）により実行検証もできないため、このセッションでは実装を見送り。発見元: PR #4572 の Devin AI レビュー（comment_id 3532565207 / 3532565261 / 3536548604 / 3536548807）をコード追跡で確認
- [ ] BUG-044: PR #4572（StringBuilder source 移行）で StringBuilder コンストラクタの新しい intercept 経路（`CallLowerer.swift` の `isStringBuilderConstructor` + `lowerStringBuilderConstructorCall`）が `kk_string_builder_new`/`kk_string_builder_new_from_string_flat` を直接呼ぶのみで、通常のコンストラクタ経路が行う `kk_type_register_super`/`kk_object_register_itable_iface` 相当の型登録をスキップする。`kk_op_is`（`Sources/Runtime/RuntimeStringArray.swift:450-`）は String 等の組込み型は専用 `stringBase` 分岐を持つが CharSequence/Appendable のような interface 型は `nominalBase` 分岐で `runtimeObjectTypeID(rawValue:)` に依存するため、型登録が無い StringBuilder ハンドルに対する `sb is CharSequence` / `sb is Appendable` は誤って `false` を返す疑い（コード追跡で確認、実行検証は BUG-042 によりこのセッションでは不可）。BUG-038（hand-crafted Runtime オブジェクトの itable 登録漏れ）と同系統の型登録漏れパターン。発見元: PR #4572 の Devin AI レビュー（comment_id 3537407331）をコード追跡で確認
- [ ] BUG-045: Golden.Sema ハーネスの合成序数正規化（`GoldenHarnessSemaComparisonNormalizer.rewriteOrdinalMatches`、対象は `__local_N`/`$N`/`__for_N` 等）が、生の raw ID（`ExprID`/`SymbolID` の値をそのまま埋め込んだ文字列）を`GoldenHarnessDump.renderSemaOutput`/`GoldenHarnessStableRenderContext.stableKey` で**文字列比較ソート**した後に初出順で 0 から振り直す実装になっている。raw ID の桁数（例: 3桁→4桁の 999→1000 境界）がローカル変数群の宣言順スパンをまたぐと、文字列ソートが数値順と食い違い、ゴールデン出力上の宣言順が入れ替わる（例: `outer`/`client1`/`client2`/`file1`/`file2` が実際の宣言順より前に来る）。コンパイラの実際の意味論（シンボル名・型・kind・呼び出し解決）は完全に等価で実害はないが、stdlib バンドル内容を追加/削除するだけで無関係な golden ファイルが壊れる — PR #4624 で `Tests/CompilerCoreTests/GoldenCases/Sema/companion_object_private_access.golden` が該当（`Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt`/`KClassMemberIntrospection.kt` 新規追加が raw ExprID のベースラインをシフトさせたことが引き金と推定）。恒久修正は `rewriteOrdinalMatches`/`stableKey` 側でゼロ埋め比較または数値ソートに直すこと。本PRのマージ作業中、masterの取り込みの度に同じgolden(`companion_object_private_access.golden`)が繰り返し再発（2026-07-08、2026-07-16、2026-07-18 の少なくとも3回再生成が必要だった）。発見元: PR #4624 の CI 失敗調査タスク（`Full Swift Tests (CompilerCoreTests shard 0/3)`）
- [ ] BUG-139: bundled `RangeMembership.kt` の `rangeIsEmpty<T : Comparable<T>>` が source-backed stdlib の型検査をハングさせる（`kswiftc --emit kir Scripts/diff_cases/hello.kt` が完了しない）。最小再現: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeMembership.kt` を注入した状態で `Scripts/diff_cases/hello.kt` をコンパイル。Int/Long/Char 専用 helper への分割で回避 — 発見元 `CI-4669` / PR #4669 open
- [ ] BUG-140: golden ハーネスの Sema symbol 一覧ソートが `GoldenHarnessDump.swift` の `requiredSymbols.sorted { ctx.stableKey(...) < ... }` で素の文字列比較を使っており、`__local_N` 等の合成スコープ名に埋め込まれた生の（ゼロ埋めなし）arena 序数が桁数境界をまたぐと表示順が崩れる（例: `"__local_10002" < "__local_9874"` が文字列比較では真になる。`'1' < '9'` のため）。この境界は bundled stdlib 側の式数が変わるだけで無関係なテストケースの golden 表示順を壊しうる。最小再現: `Tests/CompilerCoreTests/GoldenCases/Sema/companion_object_private_access.kt`（本 PR の BUG-038 対応で `RangeMembership.kt` を1関数→3関数に分割し bundled stdlib の式数が+約30 増えた副作用で、`client2`/`file1`/`file2` の local ordinal が 9999→10000 をまたぎ表示順が崩れて CI 落ち。`GoldenHarnessWorker` を直接実行し、master 版 `RangeMembership.kt` に戻すと境界をまたがず再現しないことを確認済み。3回連続実行で出力が完全一致し非決定性ではないことも確認済み）。`.compare(_:options:.numeric)` に変更して修正。他297件の Sema golden を body 参照順の単調性で静的検査し、他に同種の崩れがないことを確認済み（0件）— 発見元 `CI-4669` / PR #4669 open
- [x] DEBT-KIR-001: `Sources/CompilerCore/KIR/CallLowerer+SafeMemberCalls.swift` の vtable dispatch gate を解除。`kk_alloc` / `KTypeInfo` vtable は raw heap object fallback として残しつつ、既存 `kk_object_new` ベースの class/object/object-literal allocation は itable と同型の object-local vtable method registry を登録し、`kk_vtable_lookup` が override 実装を取得できるようにした。`VirtualDispatchTests` と backend 実行テストで open-class / safe-call 経路を検証済み
- [x] DEBT-KIR-003: `Sources/CompilerCore/Lowering/ABILoweringPass+NonThrowingCallees.swift` の手書き約 1,300 行 Set リテラルを `RuntimeABISpec` 由来の導出へ置換する。`RuntimeABIFunctionSpec` に throwing 属性が無いため throwing 情報が二重管理になっている — spec へ `isThrowing` フィールドを追加し、既存手書きリストとの全件突き合わせ検証を経て自動導出へ移行する（non-throwing callee cleanup と runtime/compiler ABI validation とも整合）
- [ ] DEBT-KIR-004: 自己参照ではない `x or y` において、`y` が直前の関数呼び出し結果（例: `String.indexOf`）の場合に右オペランドが無視され 0 として計算されるバグを調査・修正する。再現: `val value = alphabet.indexOf(c); val r = 0 or value` は `r == 0`（誤り、正しくは `value`）になるが `value or 0` は正しく計算される。KSP-482 (#4625) の `Sources/CompilerCore/Stdlib/kotlin/io/encoding/Base64.kt:107` (`decodeRaw`) でオペランド順序を入れ替えるワークアラウンドを適用済み（コメント参照）。`and`/`xor` 等の他ビット演算子でも同型の問題がないか要確認。**調査結果（2026-07-15）: 現行 HEAD（`8f3c04fb4c`、PR #4625 マージ後）ではこのバグは再現しない。** `.build/debug/kswiftc` を実際にビルドし、(1) TODO.md 記載の最小再現（`val value = alphabet.indexOf(c); val r = 0 or value` / `value or 0`）を単独関数で実行、(2) `decodeRaw` と同型の `while` ループ＋self-referential `var buffer` アキュムレータで `buffer = (buffer shl 6) or value`（ワークアラウンド適用前の順序）を実行し `"SGVsbG8="` を `"Hello"`（バイト列 72,101,108,108,111）へ正しくデコード、(3) `and`/`xor`/`shl`/`shr`/`ushr` それぞれを Int/Long・両オペランド順序・self-referential アキュムレータループで検証して Python で独立計算した期待値と完全一致、(4) 実際の `Base64.kt` のワークアラウンドを一時的に除去し、既存 `Base64EdgeCasesTests`（`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+Base64EdgeCases.swift`）と同一の14ケースを手動実行して全一致、(5) 上記 (2)(3) を `Scripts/diff_kotlinc.sh` で実 kotlinc（kotlinc-jvm 2.4.0）と突き合わせて PASS、をそれぞれ確認した。**対応: ワークアラウンドを除去**し `Base64.kt` を自然な `buffer = (buffer shl 6) or value` に戻した。再発防止として `Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+BitwiseOperatorArgumentOrder.swift`（XCTest 統合テスト、6 演算子 × Int/Long × 両オペランド順序 + self-referential アキュムレータループ）と `Scripts/diff_cases/bitwise_operator_call_derived_operand.kt`（kotlinc 比較ケース、diff_kotlinc.sh で PASS 確認済み）を追加。**推定される真因**: PR #4625（2026-07-12 マージ）から本調査時点までの間に着地した他の数値/ランタイム関連修正（`bda5fa2568` KSP-466 ULong division/modulo 修正、`24e43cce5d` vararg Any-element boxing 修正等）のいずれかが副次的に解消したと推定されるが、当時の再現バイナリが残っていないため bisect による厳密な特定はできていない。**環境注記**: 本調査を行ったサンドボックスは Xcode.app 未インストール（Command Line Tools のみ）のため `swift test`（XCTest ベース）が一切ビルドできず、追加した XCTest 統合テストは同環境では未実行（CI では実行される想定）。代わりに `kswiftc` 実バイナリの直接実行と `Scripts/diff_kotlinc.sh` による実 kotlinc との突き合わせで検証した。修正 PR: #4844（マージ後に `[x]` 化する）
