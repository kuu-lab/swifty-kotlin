# diff_kotlinc skip inventory

最終更新: 2026-07-14

この文書は `Scripts/diff_cases` の `DEBT-DIFF-*` 付き `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を、JVM kotlinc reference に戻すべきケースと、別 runner / 別テストへ移すべきケースへ分けるための棚卸しである。

集計コマンド:

```bash
find Scripts/diff_cases -type f \( -name '*.kt' -o -name '*.kts' \) -print0 \
  | xargs -0 rg -n 'DEBT-DIFF-[0-9]{3}'
```

## 方針

- `diff_kotlinc.sh` に戻す条件: JVM kotlinc が同じ入力を同じ target / classpath / runtime mode でコンパイル・実行でき、stdout / exit code を oracle にできること。
- JVM kotlinc が oracle にならない target-specific ケースは、`diff_cases` から削るのではなく、target 専用 runner、compiler diagnostic/golden、または runtime unit test の owner を明示する。
- 依存 jar だけで解けるものは、case directive または harness option で classpath / java flags を注入して通常 diff に戻す。
- `KSWIFTK_DIFF_IGNORE` は古い別名として扱う。新規 skip は `SKIP-DIFF (DEBT-DIFF-xxx): reason` に統一する。

## run_case の compile exit code 一致判定について（2026-07-08）

2026-07-08 以前の `run_case`（`Scripts/diff_kotlinc.sh`）は、reference（kotlinc）と candidate（kswiftc）の**両方がコンパイルに失敗**し、かつ **exit code が偶然一致**した場合、コンパイルエラーの内容を一切比較せず無条件で `PASS` と判定していた。実行結果（stdout）比較は `ref_compile_exit == 0 && cand_compile_exit == 0` の分岐内でのみ行われるため、両方失敗のケースはそもそもこの比較に到達しない。

この結果、reference と candidate が全く無関係な理由で失敗しているだけのケースが「PASS」として長期間見過ごされていた。実例: `random_extended.kt` は kotlinc 側が非標準 API（`Random.nextFloat(until)`）呼び出しで exit 1、kswiftc 側は無関係な `nextBytes` の実装バグで exit 1 となり、exit code が一致するため PASS 扱いになっていた（分離後: [`random_nextfloat_range_overloads.kt`](../Scripts/diff_cases/random_nextfloat_range_overloads.kt) / [`random_nextbytes.kt`](../Scripts/diff_cases/random_nextbytes.kt)）。

2026-07-08 の修正で、`ref_compile_exit != 0 && cand_compile_exit != 0 && ref_compile_exit == cand_compile_exit` の場合は無条件で `FAIL` として扱うよう変更した（`ref`/`cand` 双方の compile stderr は artifact の `compile_stderr.diff` に保存されるため、個別に原因を切り分けられる）。この変更により新たに顕在化した「両方失敗」ケースは DEBT-DIFF-007 として棚卸しした。

## 現在値

件数は実測値（`find Scripts/diff_cases -type f \( -name '*.kt' -o -name '*.kts' \) -print0 | xargs -0 rg -o 'DEBT-DIFF-[0-9]{3}' -N | sort | uniq -c`）に同期する。

| Debt | 件数 | 主因 | 優先アクション |
| --- | ---: | --- | --- |
| DEBT-DIFF-001 | 19 | JVM kotlinc reference 不成立、外部 jar / runtime-only | keep / runner / dependency injection を個別決定 |
| DEBT-DIFF-002 | 4 | script 起動 timeout と top-level execution parity | script timeout 分離後に `--force-run-skipped` で再判定 |
| DEBT-DIFF-003 | 12 | advanced coroutine / channel / Flow / structured concurrency | API 領域ごとに STDLIB-CORO / DEBT-CORO へ分割。cancellation 2 件は解除済み（`coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`） |
| DEBT-DIFF-004 | 0 | value class boxing / generics / interface / collection parity（解消済み） | — |
| DEBT-DIFF-005 | 6 | common stdlib / runtime surface gap、または synthetic surface | API 領域別に実装 owner と reference 可否を分離 |
| DEBT-DIFF-006 | 3 | type inference / variance / boxed numeric lowering | diagnostic case または parity regression へ分解 |
| DEBT-DIFF-007 | 76 | compile-exit parity fix により顕在化した両失敗ケース | diagnostic golden / owner / 実装へ個別に triage |

## DEBT-DIFF-001: reference target / classpath / runtime-only

### keep skip: JVM kotlinc を oracle にしない

| 領域 | cases | 理由 | 次アクション |
| --- | --- | --- | --- |
| Kotlin/Native / cinterop | `native_annotations.kt`, `native_api.kt`, `platform_info.kt`, `system_get_time_nanos.kt` | `kotlin.native.*`, `kotlinx.cinterop.*`, Native-only API は JVM reference で解決不能 | Native surface の Sema / golden または target 専用 smoke へ移す |
| Kotlin/JS | `js_annotations.kt`, `js_api.kt` | `kotlin.js.*` / JS external declarations は JVM reference で解決不能 | JS/Wasm stub cleanup の target-out backlog と接続する |
| Runtime-only system API | `system_process_start_nanos.kt` | `System.processStartNanos()` は KSwiftK runtime 独自 API | Runtime unit test または candidate-only smoke に移す |
| Runtime-only UUID API | `uuid_basic.kt` | KSwiftK UUID API が JVM kotlinc reference に無い(棚卸し時点で本表に未記載だった案件を追加) | Runtime unit test または candidate-only smoke に移す |
| custom JDBC runtime | `jdbc_basic.kt`, `prepared_statement_complete.kt`, `resultset_complete.kt`, `connection_validation.kt`, `transaction_management.kt` | `jdbc:kswiftk:memory` driver は kotlinc/JVM 側に無い | SQLite/JDBC reference driver を注入するか、Runtime JDBC suite へ移す |

### runner / dependency injection で戻せる候補

| 領域 | cases | 現状 | 次アクション |
| --- | --- | --- | --- |
| KMP expect/actual | `kmp_common.kt` | kotlinc に multiplatform flags を渡していない | case-specific `KOTLINC_FLAGS` で再現できるか検証し、不可なら KMP runner へ分離 |
| serialization | `custom_serializer.kt`, `dataclass_serialization.kt`, `json_serialization.kt`, `collection_serialization.kt` | `kotlinx-serialization` jar / plugin が無い | dependency injection だけで動く範囲と compiler plugin 必須範囲を分ける |
| SLF4J / logging | `logging_basic.kt`, `logging_advanced.kt` | `org.slf4j` jar / runtime-only logger が無い | `slf4j-api` + binding 注入で戻せる basic と runtime-only advanced を分ける |
| compiler plugin API | `compiler_plugin_api.kt` | case 自体は self-contained に見えるが skip 理由が generic | `--force-run-skipped` で再判定し、reference 阻害が無ければ DEBT-DIFF-006 か通常 diff へ移す |
| `kotlin.uuid` | `uuid_basic.kt` | skip 理由は「KSwiftK UUID APIs」としているが実体は標準 `kotlin.uuid.Uuid`（`@OptIn(ExperimentalUuidApi)` 必要）。`version()` / `variant()` / `nameUUIDFromBytes()` / `toLongs()`（Pair 返し）/ 非推奨化されていない `LEXICAL_ORDER` など、実 API との一致が未検証のメンバーを使用している | 実 API(kotlinc 同梱 `kotlin-stdlib-sources.jar` で照合)に合わせてテストを絞り込むか、`Stdlib/kotlin/uuid/Uuid.kt` 実装側を直すかを判断してから通常 diff へ戻す |

`path_basic.kt`（`kotlin.io.path`）は 2026-07-09 に解除済み: `import kotlin.io.path.Path` は `Path()` ファクトリしか import せず、`createDirectories` / `exists` / `isDirectory` / `writeText` / `isRegularFile` / `name` / `readText` / `readLines` / `deleteIfExists` 等の拡張関数・拡張プロパティは `kotlin.io.path` の別トップレベル宣言のため unresolved reference になっていたのが真因（`resolve` / `root` / `nameCount` / `relativize` / `normalize` / `isAbsolute` / `startsWith` / `endsWith` / `getName` 等は `java.nio.file.Path` のネイティブメンバなので import 不要で解決していた）。`import kotlin.io.path.*` に変更し、`--force-run-skipped` で reference/candidate 一致を確認した上で通常 diff に戻した。

注記: `uuid_basic.kt` は 2026-07-09 時点でこれまで本表・上表いずれにも記載が無いまま `DEBT-DIFF-001` skip が付与されていたことが判明したため、上表に追加した。`path_basic.kt` 解除前の実ファイル数は本表のカウント（22）より1件多い23件であり、カウント欄はこの解除で23→22になっている(旧来の表記と数値上一致するのは偶然)。`uuid_basic.kt` 自体の skip 解除は本件のスコープ外(別途調査中)。

`uuid_basic.kt`(旧 SKIP-DIFF 理由: 「uses KSwiftK UUID APIs that are not available in the kotlinc JVM reference」)は棚卸し対象外のまま残っていたが、`--force-run-skipped` で実測した結果 reference (kotlinc 2.4.0) 側のみが `version()`/`variant()`/`toLongs()`/`mostSignificantBits`/`leastSignificantBits`/`LEXICAL_ORDER`/`nameUUIDFromBytes()` で unresolved reference・internal アクセス・deprecation error になり、candidate (kswiftc) はそのまま通ってしまうことを確認した。`kotlin-stdlib-sources.jar`(kotlinc 2.4.0 同梱)と照合すると、これらは `java.util.UUID` の命名(`version`/`variant`/`nameUUIDFromBytes`)と混同したと見られる非標準メンバーで、実 `kotlin.uuid.Uuid` には存在しない。同じ問題は2026-04-07にも一度 `88ff2ee1b8`(`add-skip-diff-native-annotations` ブランチ、未マージ)で個別に修正されていたが、その後 KSP-476 でテストが拡張された際に非標準メンバーが再混入していた。今回はテスト側からこれら非標準メンバーの呼び出しと、実 API では `@DeprecatedSinceKotlin(errorSince = "2.4")` で hard error になる `LEXICAL_ORDER` の呼び出しを削除し、`fromLongs` を既知の定数値で検証する形に置き換えて、実 kotlinc 2.4.0 / kswiftc 双方で出力が完全一致することを確認した上で SKIP-DIFF を撤廃し通常 diff に戻した。`Stdlib/kotlin/uuid/Uuid.kt` 側の `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/`LEXICAL_ORDER` 実装自体は今回変更していない(削除するか candidate-only 扱いにするかは別途要検討)。

`path_basic.kt`（`kotlin.io.path`）は 2026-07-09 に解除済み: `import kotlin.io.path.Path` が `Path()` ファクトリしか import しておらず、`createDirectories` / `exists` / `writeText` 等の拡張関数が JVM 側で unresolved になっていたのが真因（`resolve` / `relativize` / `normalize` 等は `java.nio.file.Path` のネイティブメンバなので import 不要で解決していた）。`import kotlin.io.path.*` に変更して通常 diff に戻した。

`uuid_basic.kt` は本表に未記載だが `DEBT-DIFF-001` skip 済みで、"keep skip" 表にも含まれていない。skip 理由コメントは「KSwiftK UUID APIs」としているが、実体は `kotlin.uuid.Uuid`（`@OptIn(ExperimentalUuidApi)` 付き）という標準 stdlib API であり、`path_basic.kt` と同様に reference 側の import/opt-in 不足が真因の可能性がある。要再判定（別 backlog 化）。

## DEBT-DIFF-002: script-style cases

| グループ | cases | blocker | 次アクション |
| --- | --- | --- | --- |
| timeout-only suspect | `script_imports.kt`, `script_repl_interactive.kt`, `script_repl_patterns.kt` | script mode は `kotlinc -script` の compile + run を `RUN_TIMEOUT` で縛っている | script 専用 timeout を `COMPILE_TIMEOUT` 系へ分離し、再実行して pass なら skip を外す |
| top-level functions / custom declarations | `script_function_basic.kt`, `script_function_advanced.kt`, `script_toplevel_functions.kt`, `script_import_custom.kt` | KSwiftK 側の top-level script execution と kotlinc script mode の一致未確認 | timeout 分離後に `--force-run-skipped` で実測し、失敗が Sema / lowering 起因なら通常 `.kt` parity case へ分割 |

既に skip されていない `script_*.kt` が複数あるため、script 全体ではなく上記 7 件だけを再判定する。

`script_import_stdlib.kt` は解除済み: `shuffled()` を `shuffled(Random(42)).sorted()` に変更し、出力順序に依存しない決定論的検証にした(`sequence_shuffled.kt` と同じ idiom)。KSwiftK の `Random` は JVM kotlinc と PRNG アルゴリズムが異なる(xorshift64\* 系の自前実装で XorWow ではない、`KSP-466`)ため、seed を固定しても生の並び順は一致しない。なお、ローカル既定の `RUN_TIMEOUT=10s` は `kotlinc -script` の起動コストだけで超過する(`script_import_stdlib.kt` に限らず `script_hello.kt` など他の非 skip ケースでも同様に再現する、この環境固有の傾向)。CI は `DIFF_RUN_TIMEOUT=30` を使用しており、その設定なら安定して pass する — timeout-only suspect グループの再判定でも同じ値を使うとよい。

## DEBT-DIFF-003: advanced coroutine / channel / Flow

`Scripts/diff_kotlinc.sh` は `kotlinx.coroutines` import を検出して `kotlinx-coroutines-core-jvm` を取得できるため、現在の skip 主因は reference classpath ではなく KSwiftK 側の API / runtime parity である。

| 領域 | cases | owner |
| --- | --- | --- |
| lazy/deferred coroutine start (cancel-before-first-run, `CoroutineStart.LAZY`) | `coroutine_exception_handling.kt`, `coroutine_edge_cases.kt` | `STDLIB-CORO-001` と `DEBT-CORO-003` |
| cancellation（解除済み） | ~~`coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`~~ | `currentCoroutineContext()`/`ensureActive()`/`NonCancellable`/`CoroutineContext.isActive` を追加し、`withTimeoutOrNull` の null 判定バグ（`runtimeNullSentinelInt` ではなく生の `0` を返していた）と `coroutineScope`/`supervisorScope` の直接 throw 握りつぶしバグ（`outThrown` を forward していなかった）、および `job.join()`/`Job.await()` が返却後にハンドルを解放し join 後の `isCancelled` 参照が use-after-free になっていたバグを修正して通常 diff へ復帰 |
| CoroutineScope lifecycle（未解除） | `coroutine_scope_lifecycle.kt` | `CoroutineScope.launch { }` は `CoroutineLoweringPass+LauncherSupport.swift` の `rewriteCoroutineScopeLaunchCall`/`rewriteZeroArgCoroutineScopeLauncherCall` でレシーバを保持したまま entryPoint/functionID split する形に対応済み（`kk_coroutine_scope_launch(scopeHandle, entryPointRaw, functionID)`、ローカル変数レシーバで動作確認済み。キャプチャ付きラムダは未対応で `KSWIFTK-CORO-0003` を返す）。この diff case は依然 2 件の別バグでブロックされている: (1) `private val scope = CoroutineScope(...)`（型注釈なしのクラスプロパティ）がシブリングのメンバ関数チェック時に未解決型のまま扱われる `typeCheckClassLikeMembers`（`DeclTypeChecker+ClassAndObjectChecking.swift`）のパス順序バグ、(2) 型注釈を付けて (1) を回避しても、非ctor引数のクラスプロパティ初期化子（`private val scope: CoroutineScope = ...`）がインスタンスへ書き込まれず（コンストラクタに `kk_array_set` 相当の書き込みが無い）`kk_coroutine_scope_launch` が invalid scope handle で fatalError する、`class-instance-property-init-storage-bug` と同種の問題（PR #4691 `claude/recursing-rhodes-5a8c58` で対応中、未マージ）。両方の解消後に `SKIP-DIFF` を外す |
| structured concurrency / Deferred / Supervisor | `coroutine_deferred.kt`, `coroutine_structured_concurrency.kt`, `coroutine_supervisor_job.kt` | Job hierarchy / async-await / supervisor semantics の runtime task |
| Channel / produce / Flow backpressure | `channel_basic.kt`, `coroutine_channels_advanced.kt`, `coroutine_flow_backpressure.kt` | `DEBT-CORO-002` の producer / channel runtime と Flow lowering |
| sync primitives | `coroutine_mutex_semaphore.kt` | Sema: `launch { }` 直下の `Mutex.withLock` / `Semaphore.withPermit` 呼び出しが overload 解決に失敗する既存バグ |

`coroutine_base_edge_cases.kt`（direct suspend call のデッドロック、try/catch 内 suspend call の例外もみ消し）と
`coroutine_context_switching.kt`（`withContext` の期待型ハンドリング）は 2026-07-09 に skip 解除済み。

残る2件は当初 "advanced coroutine API 未実装" という一般的理由だったが、実際の root cause は次の通りに絞り込めた:

- `coroutine_exception_handling.kt`: `async { throw ... }.await()` の例外もみ消しは `kk_kxmini_async` が完了時に continuation の
  `thrownException` を確認せず `task.complete(with: result)` を無条件に呼んでいたバグで、これは修正済み
  （`kk_kxmini_launch_with_exception_handler` と同じパターンを適用）。残る唯一の差分は、`launch{}` 直後に同期 `cancel()`
  すると JVM 参照には出ない `"cancelled cleanly"` 行が余分に出力されること。原因は `launch{}` が本体を実 GCD キューへ
  即座にディスパッチするため、cancel が本体の最初のサスペンションポイント到達より先に届くべきタイミングを再現できないこと
  （kotlinx の `runBlocking` は協調的シングルスレッドイベントループで、親がサスペンドするまで子は一切実行されない）。
- `coroutine_edge_cases.kt`: `launch(start = CoroutineStart.LAZY) { ... }` がそもそもコンパイルできない
  （`CoroutineStart` 型・`launch(start:, block:)` オーバーロードを意図的に未登録のまま）。理由は
  `rewriteLauncherCall` の dispatcher-aware path が 2 引数 `launch` の第一引数を無条件に `CoroutineDispatcher` として
  `kk_kxmini_launch_with_dispatcher` に渡すため、`CoroutineStart` 値を渡すと実行時にクラッシュ（`kk_job_is_cancelled`
  内で `EXC_BAD_ACCESS`）する。type-aware disambiguation なしで登録するのは危険なので見送った。

両ケースとも、根っこは同じ「ジョブの genuine な "pending, not yet started" 状態が無い」という欠落に行き着く。
`CoroutineStart.LAZY` を実装するにも、`launch{}` 直後の同期 cancel タイミングを JVM と揃えるにも、
実際に本体を dispatch する前に "start()/最初の親 suspend まで待つ" フェーズを持つ RuntimeJobHandle 状態が要る。
scheduler の分岐が広いため、単発の bug fix ではなく別 task として切り出すべき。

解除順は、`runBlocking` + simple suspend、`withContext`、`async/await`、Channel、Flow、Supervisor / cancellation の順にする。

### `coroutine_mutex_semaphore.kt` 個別メモ (2026-07-09)

`Semaphore.withPermit` の Sema 登録・KIR lowering (`kk_semaphore_withPermit` の引数分割)・Runtime 実装、および `java.util.concurrent.atomic.AtomicInteger` の直接構築対応は実装済み（このコミットで追加）。それでも本ケースが `--force-run-skipped` で FAIL するのは別原因: `mutex.withLock { ... }` / `semaphore.withPermit { ... }` を `launch { }` の trailing lambda 直下に置くと `KSWIFTK-SEMA-0002 No viable overload found for call` になる。`runBlocking { }` 直下では同じ呼び出しが解決できる（`mutex.withLock` は変更していない既存コードだが同様に失敗する＝今回追加した2機能のバグではない）。加えて `Mutex.withLock` を suspend でない `fun main()` 直下・コルーチンビルダー外から呼ぶとコンパイラがハングする再現ケースも確認した（`repro8` 相当、120秒 timeout）。原因調査は `launch` の trailing lambda 本体に対する suspend コンテキスト伝播 / overload 解決まわりと推測されるが、未特定。次のアクションは Sema の `CallTypeChecker.swift` 側で `launch` の lambda 引数を suspend context として正しく伝播できているか調査すること。
### structured concurrency / Deferred / Supervisor 詳細（2026-07-10 調査）

3ケースとも当初想定（「不足APIを足すだけ」）より深いバグに当たった。調査で Sema 側の一般的な型推論バグを複数発見・修正済みだが、各ケースとも KIR lowering / runtime 層に別種の未解決ブロッカーが残る。

**この調査で修正済み（3ケース共通の前提を直した Sema 修正、副作用として広く安全性を確認済み）:**

- `kotlin.coroutines` パッケージが default import list に無く、`coroutineContext` が unresolved になっていた（`ScopeBuilder.swift`）。
- `IntRange.map` が transform ラムダの実際の戻り値型を無視し、常に `List<Any>` を返していた（`CallTypeChecker+RangeMemberFallback.swift`）。`(1..5).map { n -> ... }` の要素型が壊れていたため `it.await()` 等の後続メンバー呼び出しが unresolved になっていた。
- `async`/`coroutineScope`/`supervisorScope` が常に `Any`（または raw `Deferred`）を返し、trailing lambda の実際の本体型を読み戻していなかった（`CallTypeChecker.swift` の `adjustedReturnType` 分岐、新規 `CallTypeChecker+CoroutineBuilderReturnType.swift`）。`Deferred` はクラスレベル型パラメータを持たないため、`.await()` の戻り値型は `bindDeferredElementType`/`deferredElementType`（`SemanticsModels.swift`、Flow の `flowElementType` と同型のサイドチャネル方式）で追跡するようにした。`LocalDeclTypeChecker.swift` で `val`宣言時にこのマーカーを伝播する。
- Kotlin の「ラムダの期待戻り値型が `Unit` のとき、本体の実際の値は破棄されボディの型は問わない」という言語仕様が未実装だった。`inferLambdaLiteralExpr`（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）がラムダ本体を型推論する際に `expectedType: Unit` をそのまま本体式（例: 関数呼び出し）に伝播しており、本体が非Unit値を返す呼び出し（例 `repeat(3) { i -> someIntFn(i) }`）の呼び出し解決自体が「戻り値がUnitと非互換」として `No viable overload found for call` になっていた。**これはコルーチンと無関係な一般的なSemaバグ**（`repeat`/`forEach` 等あらゆる `(T) -> Unit` パラメータで発生）で、`coroutine_structured_concurrency.kt` の `repeat(3) { i -> launch { ... } }` パターンを直接ブロックしていた。修正: 本体の `expectedType` は expected return が `Unit` の場合 `nil` に落とす。
- 上記5件は `bash Scripts/diff_kotlinc.sh` で以下の回帰確認済み（regressionなし）: `coroutine_scope.kt`, `job_basic.kt`, `supervisor_scope_basic.kt`, `async_await.kt`, `launch_basic.kt`, `range_hof.kt`, `repeat.kt`, `array_hof.kt`, `collection_hof.kt`, `stdlib_collection_hof.kt`, `string_hof.kt`, `lambda_it.kt`, `lambda_with_receiver.kt`, `sequence_forEach_flatMap.kt`, `set_map_filter_foreach.kt`, `map_entries_hof.kt`, `closure_multi_capture_hof.kt`, `destructuring_lambda.kt`, `labeled_return_lambda.kt`（計19ケース）。

**各ケースに残る個別ブロッカー:**

- `coroutine_deferred.kt`: `CoroutineStart`（enum, `.LAZY` 含む）と `awaitAll` が未登録（Sema追加で対応可能）。加えて、`jobs.map { it.await() }` のように **Iterator 経由で取得した `Deferred`/`Job` に対して `.await()`（内部で `Unmanaged.takeRetainedValue()` する runtime 関数）を呼ぶと `swift_unknownObjectRetain` で SIGSEGV する**深刻なランタイムバグを発見（直接インデックスアクセス `jobs[0].await()` や `.forEach { it.isActive }`（await以外）は正常動作するため、Iterator経由取得値への `.await()` 呼び出しに固有）。原因は未特定（ABI boxing / Iterator lowering の追加調査が必要）。`awaitAll` の実装がもし内部で同様の反復処理をするなら同じ問題に当たる可能性が高い。
- `coroutine_structured_concurrency.kt`: `repeat(3) { i -> launch { sum += (i+1) } }` の Sema型検査は通るようになったが、**`coroutineScope {}` ブロックが外側の可変変数をキャプチャして変更すると KIR lowering が失敗する**（最小再現: `var sum = 0; coroutineScope { sum += 1 }` だけで `KSWIFTK-CORO-0003: Coroutine launcher 'coroutineScope' passed 0 argument(s) but referenced suspend function expects 1.`）。同じパターンを `launch {}`/`async {}` で試すと正常動作するため、`coroutineScope`（おそらく `supervisorScope`/`runBlocking` も同様）の呼び出し書き換え箇所（`CoroutineLoweringPass+CallRewriting.swift` 付近、capture変数を追加引数として渡す処理）固有のバグ。
- `coroutine_supervisor_job.kt`: `SupervisorJob()`・トップレベル関数としての `CoroutineScope(context)` が未登録（cascadeで `supervisor.cancel()` も ambiguous overload になっている）。ランタイム側には `kk_supervisor_scope_new` / `kk_coroutine_scope_new`（`RuntimeCoroutineScope(isSupervisor:)` ベース）が既に存在するため実装の土台はあるが、`SupervisorJob()` を `Job` 互換ハンドルとして返しつつ `CoroutineScope(coroutineContext + supervisor)` の `+` 合成をどう扱うか、および `scope.launch { }` という明示的レシーバでの呼び出しを既存の暗黙レシーバ実装（`RuntimeCoroutineScope.current`）とどう両立させるかの設計が必要。`Job` ハンドルと `RuntimeCoroutineScope` ハンドルは異なる runtime 表現（前者は `RuntimeJobHandle` 経由の手動 retain/release、後者は別クラス）のため、安易に混用すると上記と同種の型混同クラッシュを起こすリスクがある。

**次アクション（優先度順）:**

1. `coroutine_supervisor_job.kt`: `SupervisorJob()` / `CoroutineScope(context)` の Sema 登録 + runtime 実装（型混同を避ける設計を先に固める）。3ケース中もっとも「不足APIの追加」に近く、対応可能性が高い。
2. `coroutine_structured_concurrency.kt`: `coroutineScope{}` の capture-lowering バグの原因調査（`CoroutineLoweringPass+CallRewriting.swift`）。
3. `coroutine_deferred.kt`: Iterator経由 `.await()` の SIGSEGV バグの原因調査（ABI boxing / Iterator lowering）。`CoroutineStart`/`awaitAll` の Sema 登録は独立して先に進められる。

## DEBT-DIFF-004: value class parity（解消済み、2026-07-12）

5 ケースとも `SKIP-DIFF` を解除し、通常の `diff_kotlinc.sh` 経路で green。

| cases | 主な責務 | 解消した根本原因 |
| --- | --- | --- |
| `value_class_boxing_boundaries.kt` | Lowering / Runtime ABI | `Any`, nullable, cast, collection element 境界の box/unbox insertion |
| `value_class_generics.kt` | Sema / KIR | generic value class、bounds、`sortedBy` lambda receiver の型推論 |
| `value_class_collections.kt` | Lowering / Runtime ABI | List / Map / Array storage、HOF iteration 境界、および boxed value class の hashCode/equals 不整合（`runtimeAnyHashCode` に `RuntimeObjectBox` ケースが無く pointer-identity hash にフォールバックしていた） |
| `value_class_interfaces.kt` | Sema / KIR / dispatch | value class の interface 実装と boxed interface dispatch（itable dynamic dispatch, `kk_itable_lookup_dynamic`） |
| `value_class_interop.kt` | Lowering / primitive ABI | Long / Double underlying value の ABI、string interpolation、list map |

対応した分割タスク:

- Sema: value class declaration, generic value class, interface implementation, nullable value class の型表現を監査（完了）。
- KIR / Lowering: `Any` / generic / interface / collection / nullable 境界で box/unbox を挿入（完了）。
- Runtime ABI: boxed value class（interface 実装により `kk_object_new` で box されたまま残るもの）の equality / hash を検証・修正。`runtimeValuesEqual` は既に `RuntimeObjectBox` を構造比較していたが、`runtimeAnyHashCode` に対応ケースが無く、`Any.hashCode()` 経由の呼び出しが pointer-identity ハッシュへフォールバックしていた（`c1 == c2` は `true` なのに `c1.hashCode() != c2.hashCode()` という equals/hashCode 契約違反）。あわせて data class 側の `appendSyntheticDataClassHashCodeIfNeeded` も、フィールドを読み出さず `receiver, fieldOffset` を直接 `kk_any_hashCode` に渡しており同じ契約違反を起こしていたため修正。
- Regression: 上記 5 ケースを `--force-run-skipped`（さらに機材負荷を考慮し `--run-timeout 60`）で green 確認後、`SKIP-DIFF` marker を削除。

## DEBT-DIFF-005: common stdlib surface gap

| 領域 | cases | 判定 | 次アクション |
| --- | --- | --- | --- |
| `java.math.BigInteger` | `big_integer.kt` | Java interop surface gap | BigInteger を対象に残すなら Java interop task、対象外なら target-out backlog |
| KSwiftK synthetic Sequence surface | `sequence_takelast.kt`, `sequence_takelastwhile.kt`, `sequence_subtract.kt` | JVM kotlinc に無い surface | public surface として残す理由を再確認し、残すなら candidate-only test へ移す |
| Scope functions | `scope_functions_edge_cases.kt` | common stdlib gap | `let` / `also` / `with` / `apply` / `takeIf` / `takeUnless` を API 別に分解 |
| Property delegates | `property_delegate_edge_cases.kt` | delegate lowering 起因と確定（stdlib 側の `Delegates.observable`/`vetoable`/`lazy` 実装・ランタイム ABI は正しい）。クラスメンバの delegate プロパティ初期化で2件のバグを修正済みだが、残り2件（uncommitted, 別 owner）が残るため引き続き skip | 残課題（下記注記）を個別に修正してから通常 diff へ |
| Regex runtime edge | `regex_runtime_edge_cases.kt` | named group / invalid pattern parity | RuntimeRegex と diagnostic behavior の regression に分割 |
| ByteArray helpers | `string_tobytearray.kt` | `joinToString` / `contentEquals` Sema gap | ByteArray extension stubs + runtime helpers の task に分割 |
| File/use | `file_use_edge_cases.kt` | `Closeable.use` と `java.io.File` surface | `use` common helperと JVM file interop を分離 |
| Duration/time | `duration_operations.kt`, `experimental_time_edge_cases.kt` | formatting / timing-sensitive output | `Duration.toString` parity と monotonic time test determinism を分離 |
| Math/comparator | `math_trig_functions.kt`, `comparator_composition_edge_cases.kt` | math function / comparator API gap | math runtime ABI、Comparator composition API に分ける |
| ByteArray UUID bridge | `uuid_put_uuid.kt` | kswiftc の `ByteArray.putUuid`/`ByteArray.uuid`/`ByteArray.getUuid` は `HeaderHelpers+SyntheticUuidStubs.swift` の bridge-only synthetic 拡張。実 Kotlin stdlib には同名だが `java.nio.ByteBuffer` 版（JVM専用、Kotlin 2.4〜）しか無く、`ByteArray` レシーバ版も top-level の `uuid()` も存在しないため JVM kotlinc は receiver type mismatch / unresolved reference で compile error になる | `ByteArray` 版を kswiftc 独自 surface として残すなら candidate-only test へ移す。real API 互換を狙うなら `ByteBuffer` 受け口への設計変更が必要 |

`experimental_time_edge_cases.kt` は実行速度差で stdout が揺れるため、固定 clock / larger duration / unit test のどれかへ寄せてから diff に戻す。

`property_delegate_edge_cases.kt` の詳細（2026-07-09 調査）: クラスメンバの `val/var x by lazy {...} / Delegates.observable(...)/vetoable(...)` は、トップレベルプロパティ用の実装（`KIRLoweringDriver+ModuleLowering+PropertyDecl.swift`）とは別系統の実装（`MemberLowerer` / `KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift`）で lowering されており、そちらは `StdlibDelegateKind`（`lazy`/`observable`/`vetoable`/`notNull`）を想定していなかった。以下4件のバグを確認し、(1)(2) はワークツリーに修正を適用済み（未コミット）:

1. **[修正済み]** `MemberLowerer+DelegatedAndAccessorLowering.swift` の `lowerDelegateAccessor`: `.custom` 以外（`lazy`/`observable`/`vetoable`/`notNull`）の getter/setter が `kk_lazy_get_value`/`kk_observable_set_value` 等を呼ぶ際、delegate ハンドル（`$delegate_x` の値）を引数に含めていなかった（`arguments: []` / `arguments: [valueExprID]` のみ）。ランタイム ABI（`kk_lazy_get_value(handle)`, `kk_observable_set_value(handle, newValue)` 等、`RuntimeABISpec+Delegate.swift`）は handle 必須のため、実引数0/1個で宣言された LLVM 外部関数型と実体（Swift `@_cdecl` 関数）のシグネチャが食い違い、`handle` が不定値になり `null`/`0` を返し続けていた。
2. **[修正済み]** `KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift` の `emitDelegatePropertyInitializer`: メンバプロパティの delegate 初期化はコンストラクタ内で `propertyDecl.delegateExpression` のみを評価しており、トレーリングラムダ `propertyDecl.delegateBody`（`lazy` の初期化ブロック、`observable`/`vetoable` のコールバック）を一切参照していなかった。`lazy` は `kk_lazy_create` 呼び出し自体が欠落（生のクロージャ参照を直接フィールドへ copy）、`observable`/`vetoable` は `kk_*_create` の初期値のみ渡りコールバック引数が欠落していた。トップレベル実装が持つ `emitLazyDelegateInit`/`emitCallbackDelegateInit`（`lowerDelegateInitialValue`/`lowerDelegateLambdaBody` を使用）と同等のロジックを `StdlibDelegateKind` 判定つきで追加した。
3. **[未修正・delegate 固有]** パラメータ付きトレーリングラムダ（`Delegates.observable(1) { _, old, new -> println(...) }` のような `_, old, new ->` prefix 付き）の `delegateBody` 抽出（`BuildASTPhase+DeclBuilders.swift` の `makePropertyDecl` → `blockExpressions`）が、文単位区切りを前提にした汎用パーサーのため、パラメータリスト+アロー構文を正しく扱えず、コールバック本文が `unit` として消えている（`println`/比較式が一切実行されない）。`lazy` のようにパラメータなしの trailing block は正しく抽出できる。
4. **[未修正・delegate と無関係の一般バグ]** bare-name（暗黙 `this`）の compound assign / inc-dec（`count += 1`, `count++`）がクラスメンバフィールドに対して書き込みを永続化しない。`ExprLowerer+ControlFlowAndBlocks.swift` の `.compoundAssign` 処理は top-level/object-member（親 kind が nil/`.package`/`.object`）と mutable-capture-boxed のケースのみ扱い、`.class`/`.interface` 所有のフィールドは「ephemeral local」フォールバックに落ちて `ctx` 上でのみ更新され実フィールドへの `kk_array_set` を発行しない。`this.count += 1`（明示レシーバ、PR #4633 で修正済みの経路）は正しく動く。`property_delegate_edge_cases.kt` の `lazy { initCount += 1; "ready" }` はこれに該当し、`token` の値自体は (1)(2) 修正で "ready" に直ったが `initCount` は 0 のまま。最小再現: `class C { var n = 0; fun f() { n += 1 } }` で `f()` 後も `n` が 0。

3, 4 はどちらも本ケースの完全な pass に必要だが、4 は property delegate と無関係の独立した一般correctness bugであり、3 も AST パーサー層の変更を要するため、本 SKIP-DIFF 解除作業のスコープ外として別タスクに切り出した。

## DEBT-DIFF-006: inference / variance / boxed numeric lowering

| cases | 判定 | 次アクション |
| --- | --- | --- |
| `error_type_inference.kt` | compile-error expectation case | diff harness は現状 stderr parity を厳密比較しないため、diagnostic golden か error-code regression へ移す |
| `variance_generics.kt` | Sema variance checking gap | variance type checker の実装後に通常 diff へ戻す。実装前は Sema golden / diagnostic case として固定 |
| `math_rounding_functions.kt` | math API ではなく boxed `Double` iteration lowering bug | List<Double> iteration unboxing の最小再現を別 case 化し、math 関数 case から分離 |

## DEBT-DIFF-007: compile-exit parity fix により顕在化した両失敗ケース

`run_case()` は、reference と candidate がともに失敗し同じ非ゼロ終了コードを返しても、無条件に `FAIL` とするよう修正済みである。これにより顕在化した76件を、原因の個別確認が終わるまで `SKIP-DIFF (DEBT-DIFF-007)` として隔離する。

対象は diagnostic parity、enum/data class/interface/variance、common stdlib・テスト入力、Flow、reflection/metadata、JVM・時間・UUID、finally exception routing に分類する。各ケースのマーカーを起点に、diagnostic golden、実装owner、またはtarget専用runnerのいずれかへ移してからskipを解除する。

## 解除手順

1. 対象ケースだけを `--force-run-skipped` で実行する。

```bash
bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped Scripts/diff_cases/<case>.kt
```

2. reference 側だけが失敗するなら runner / classpath / target 問題として本 inventory を更新する。
3. candidate 側だけが失敗するなら Sema / KIR / Lowering / Runtime owner の task へ分解する。
4. 両者が pass したら `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を削除し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` で通常 diff を確認する。
