# diff_kotlinc skip inventory

最終更新: 2026-07-29

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
| DEBT-DIFF-001 | 19 | JVM kotlinc reference 不成立（target/classpath/runtime-only） | 2026-07-29 棚卸し完了。19件全件を再ビルドした kswiftc + kotlinc 2.4.10 で再検証し、全件 keep skip 確定（詳細は下記節） |
| DEBT-DIFF-002 | 4 | script 起動 timeout と top-level execution parity | script timeout 分離後に `--force-run-skipped` で再判定 |
| DEBT-DIFF-003 | 11 | advanced coroutine / channel / Flow / structured concurrency | API 領域ごとに STDLIB-CORO / DEBT-CORO へ分割。cancellation 2 件と `channel_basic.kt` は解除済み（`coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`） |
| DEBT-DIFF-004 | 0 | value class boxing / generics / interface / collection parity（解消済み） | — |
| DEBT-DIFF-005 | 1（解消・分割済み、2026-07-29） | 大半は既に解消/移設済み。CASE_INSENSITIVE_ORDER 誤登録（BUG-154）は `origin/master` 側で解消済み。残るのは property delegate lowering の実バグ（BUG-151/BUG-170）の1件のみ | 個別 BUG 番号で追跡（本節参照） |
| DEBT-DIFF-006 | 1 | type inference / boxed numeric lowering / compiler-plugin API | diagnostic case または parity regression へ分解 |
| DEBT-DIFF-007 | 73 | compile-exit parity fix により顕在化した両失敗ケース | diagnostic golden / owner / 実装へ個別に triage |

## DEBT-DIFF-001: reference target / classpath / runtime-only

棚卸し完了(2026-07-29、`swift build` で kswiftc を再ビルドし、kotlinc 2.4.10 で現行19件全件を再検証)。**19件全件 keep skip 確定** — dependency injection や個別 runner で通常 diff に戻せたケースは無かった。

### なぜ dependency injection では解決しないか

`Scripts/diff_kotlinc.sh` の `--kotlinc-classpath` / coroutines jar 自動取得は **reference(kotlinc)側にしか作用しない**。kswiftc は jar/classpath を一切消費しない設計で、`Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift` に手書き登録した合成シンボルだけを認識し、対応する Runtime 実装を呼ぶ。したがって candidate 側が特定の Java/Kotlin API を新たに認識するには synthetic stub の実装が要り、jar 注入は原理的に届かない。「dependency injection で実行可能化」できるのは reference 側だけが理由で落ちているケースに限られるが、以下19件はいずれも candidate 側の未実装、またはテスト内容自体が実 API 呼び出し規約と非互換という、jar 注入では解決しない理由だった。

### 確定した keep skip 一覧(19件)

| 領域 | cases | 確定理由(2026-07-29 再検証) | 恒久対応の道筋 |
| --- | --- | --- | --- |
| Kotlin/Native / cinterop | `native_annotations.kt`, `native_api.kt`, `platform_info.kt`, `system_get_time_nanos.kt` | `kotlin.native.*` / `kotlinx.cinterop.*` は JVM kotlinc に存在しない。kotlinc 2.4.10 は全件 `unresolved reference` で即失敗、kswiftc は候補シンボルとして受理し正常コンパイルすることを確認。`platform_info.kt` は一時的に `--compile-timeout 15` を超えたが、システム負荷起因の見かけ上のタイムアウトで(`--compile-timeout 60` で再実行すると `time` 計測で user 8s 程度で正常終了、CPU使用率35%と待ち時間が主でビジーループではない)、無限ハングではない | Native surface 専用の Sema golden / target-specific smoke test へ移す(JVM reference を使わない) |
| Kotlin/JS | `js_annotations.kt`, `js_api.kt` | `kotlin.js.*` は JVM kotlinc に存在しない。`error: symbol is declared in module 'kotlin.stdlib' which does not export package 'kotlin.js'` 等で即失敗を確認 | JS/Wasm stub cleanup の target-out backlog と接続する |
| Runtime-only system API | `system_process_start_nanos.kt` | `System.processStartNanos()` は KSwiftK 独自 API。kotlinc は `unresolved reference` で即失敗を確認 | Runtime unit test または candidate-only smoke に移す |
| JDBC / java.sql | `jdbc_basic.kt`, `prepared_statement_complete.kt`, `resultset_complete.kt`, `connection_validation.kt`, `transaction_management.kt` | **訂正**: 従来「custom jdbc:kswiftk driver をこの runtime が提供する」としていたが誤り。`Sources/` 全体を検索しても `DriverManager` / `java.sql` / `JDBC` / `jdbc:kswiftk` は一件もヒットせず、kswiftc は java.sql.\* を一切実装していない。再検証で `ref_compile_exit=0 / cand_compile_exit=1`(reference は素の JDK `java.sql` で普通にコンパイルが通り、candidate 側が `Unresolved reference 'DriverManager'` で落ちる)ことを確認 — reference 側の問題ではなく candidate 側の未実装機能だった。なお `jdbc_basic.kt` のみ実在し移植可能な `"jdbc:sqlite::memory:"` という URL を使っており(他4件は架空の `"jdbc:kswiftk:memory"`)、将来 JDBC 対応に着手する際の再開候補として最有望 | kswiftc に java.sql.\*(DriverManager/Connection/Statement/PreparedStatement/ResultSet 相当)の synthetic stub と対応する Runtime 実装を追加する大きめの機能追加が前提。実装後は `jdbc_basic.kt` を実 SQLite JDBC driver(`org.xerial:sqlite-jdbc`)の reference 側注入で検証し、他4件は URL を `jdbc:sqlite:` 系に書き換えてから同様に戻す |
| KMP expect/actual(単一ファイル制約) | `kmp_common.kt` | kotlinc 2.4.10 は `-Xmulti-platform` と `-Xcommon-sources=<file>` を付けても単一ファイル内の expect/actual を `'expect' and 'actual' declarations can be used only in multiplatform projects` / `expect and corresponding actual are declared in the same module` で拒否することを実測で確認した。common ソースと platform ソースを別コンパイル単位にして最終的にリンクする、genuinely 複数回起動する KMP 専用ビルドモデルが必須で、`kotlinc file.kt` 一発では原理的に表現できない。kswiftc 側も独立した expect/actual バグを抱える | harness に「1ファイルを common/platform に分割して2回コンパイル+リンクする」専用 KMP runner を新設しない限り不可能。ROI が低いため現時点では見送り、`Scripts/diff_kotlinc.sh` の対象外に据え置く |
| serialization(KSwiftK 独自 synthetic stub、実 kotlinx.serialization 非互換) | `custom_serializer.kt`, `dataclass_serialization.kt`, `json_serialization.kt`, `collection_serialization.kt` | 実 `kotlinx-serialization-core-jvm`/`kotlinx-serialization-json-jvm` 1.7.3 と kotlinc 2.4.10 同梱の `kotlin-serialization-compiler-plugin.jar` を実際に注入して再検証した。`Json.encodeToString(x)` / `decodeFromString(x)` のように明示的な reified 型引数を書かない呼び出し形は、4ファイル全てで実 Kotlin 側が `error: cannot infer type for type parameter 'T'` で拒否する(`List<Int>` のような単純な組み込み型でも同様に失敗し、compiler plugin の有無でも変化なし)。したがって dependency injection では原理的に解決しない — テストが実 API の呼び出し規約(明示的型引数、または型推論可能な文脈)に従っていない。加えて `custom_serializer.kt` は実在しない `kotlinx.serialization.Decoder`/`Encoder`(実際は `kotlinx.serialization.encoding.*` に存在し、メンバー構成も異なる)と非 generic `KSerializer` を使用しており実 API とは別物、`dataclass_serialization.kt` はローカルに独自定義した decoy `annotation class Serializable` を使っており実の `@kotlinx.serialization.Serializable` ではない。`custom_serializer.kt` は kswiftc 自身も `registerSerializer` 未解決 / Ambiguous overload で独立にコンパイル失敗することも確認した(candidate 側の既存 Sema バグ)。この synthetic stub 自体は `CLEANUP-STUB-121`(`HeaderHelpers+SyntheticSerializationStubs.swift` 削除予定、723行)で除去予定であり、当該4ケースの本質的な整理はそちらに委ねる | `CLEANUP-STUB-121` 実施時に、これら4ケースを削除するか、実 kotlinx.serialization 呼び出し規約(明示的型引数、実 `@Serializable`、実 `kotlinx.serialization.encoding.Decoder`/`Encoder`)に書き直した上で dependency injection 経由の通常 diff として再作成するかを判断する |
| SLF4J / logging | `logging_basic.kt`, `logging_advanced.kt` | kswiftc は `org.slf4j.*` を一切実装していない(`Sources/` 全体検索で0件、`Unresolved reference 'LoggerFactory'` で確認)。reference 側は実 slf4j-api + binding 注入で通す経路が既にある(2026-07-09 検証済み)が、candidate 側に synthetic stub が無い限り届かない。`logging_advanced.kt` はさらに `MDC` は実在するが import が無く、`AdvancedLogger`/`StructuredAppender` は実 SLF4J に存在しない架空 API であり、架空 API 部分を残す限り reference 側を通す余地自体が無い | kswiftc に `org.slf4j.*`(Logger/LoggerFactory/MDC 程度)の synthetic stub を追加する機能実装が前提。`logging_advanced.kt` は架空 API 部分を切り離すか削除しない限り、stub 追加後も keep skip のまま |

### 解除済みの周辺ケース(現行19件には含まれないが、過去の調査ノートに記載があったため参考として残す)

- `path_basic.kt`(`kotlin.io.path`): 2026-07-09 解除済み。`import kotlin.io.path.Path` が `Path()` ファクトリしか import せず、`createDirectories` / `exists` / `writeText` 等の拡張関数・拡張プロパティが unresolved だったのが真因(`resolve` / `relativize` / `normalize` 等は `java.nio.file.Path` のネイティブメンバなので import 不要で解決していた)。`import kotlin.io.path.*` に変更し、`--force-run-skipped` で reference/candidate 一致を確認した上で通常 diff に復帰した。
- `uuid_basic.kt`(`kotlin.uuid.Uuid`): 2026-07-09 解除済み。skip 理由は当初「KSwiftK 独自 UUID API」としていたが、実体は標準 `kotlin.uuid.Uuid`(`@OptIn(ExperimentalUuidApi)`)であり、テスト側が `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/非推奨化前の `LEXICAL_ORDER` など `java.util.UUID` の命名と混同した非標準メンバーを呼んでいたのが真因(`kotlin-stdlib-sources.jar` 同梱の実 API と照合して確認)。これら非標準メンバーの呼び出しを削除し、`fromLongs` を既知の定数値で検証する形に置き換え、実 kotlinc 2.4.0 / kswiftc 双方で出力が完全一致することを確認した上で通常 diff に復帰した。`Stdlib/kotlin/uuid/Uuid.kt` 側の `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/`LEXICAL_ORDER` 実装自体(削除するか candidate-only 扱いにするか)は本件のスコープ外で未着手。

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
| CoroutineScope lifecycle（未解除） | `coroutine_scope_lifecycle.kt` | `CoroutineScope.launch { }` は `CoroutineLoweringPass+LauncherSupport.swift` の `rewriteCoroutineScopeLaunchCall`/`rewriteZeroArgCoroutineScopeLauncherCall` でレシーバを保持したまま entryPoint/functionID split する形に対応済み（`kk_coroutine_scope_launch(scopeHandle, entryPointRaw, functionID)`、ローカル変数レシーバで動作確認済み。キャプチャ付きラムダも BUG-049 で対応済み — capture を launcher continuation 経由で転送する `kk_coroutine_scope_launch_with_cont(scopeHandle, entryPointRaw, continuation)` を追加し、`Scripts/diff_cases/coroutine_launch_capture.kt` で回帰固定）。この diff case は依然 2 件の別バグでブロックされている: (1) `private val scope = CoroutineScope(...)`（型注釈なしのクラスプロパティ）がシブリングのメンバ関数チェック時に未解決型のまま扱われる `typeCheckClassLikeMembers`（`DeclTypeChecker+ClassAndObjectChecking.swift`）のパス順序バグ、(2) 型注釈を付けて (1) を回避しても、非ctor引数のクラスプロパティ初期化子（`private val scope: CoroutineScope = ...`）がインスタンスへ書き込まれず（コンストラクタに `kk_array_set` 相当の書き込みが無い）`kk_coroutine_scope_launch` が invalid scope handle で fatalError する、`class-instance-property-init-storage-bug` と同種の問題（PR #4691 `claude/recursing-rhodes-5a8c58` で対応中、未マージ）。両方の解消後に `SKIP-DIFF` を外す |
| structured concurrency / Deferred / Supervisor | `coroutine_deferred.kt`, `coroutine_structured_concurrency.kt`, `coroutine_supervisor_job.kt` | Job hierarchy / async-await / supervisor semantics の runtime task。詳細調査結果と残ブロッカーは下記「structured concurrency / Deferred / Supervisor 詳細」節を参照 |
| Channel / produce / Flow backpressure | `coroutine_channels_advanced.kt`, `coroutine_flow_backpressure.kt` | `DEBT-CORO-002` の producer / channel runtime と Flow lowering |
| sync primitives | `coroutine_mutex_semaphore.kt` | KSP-677 で Sema の overload 解決バグ（`KSWIFTK-SEMA-0002`）を解消し、BUG-049 で `launch { }` 本体のキャプチャ付き suspend 呼び出しの coroutine lowering feature gap（`KSWIFTK-CORO-0003`）も解消（回帰は `coroutine_launch_capture.kt`）。残ブロッカーは CORO-0003 とは別の既存 runtime GC-under-parallelism クラッシュ（100+ 並列 launch で `swift_retain` が SIGSEGV）と `delay` 依存 |

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

**更新 (2026-07-24, KSP-677)**: Mutex/Semaphore ラッパー層を bundled Kotlin source 化する際、`withLock`/`withPermit` を canonical generic `suspend fun <T> ...(action: () -> T): T` として書けるよう、generic 高階関数が Unit 本体ラムダから型変数 `T` を推論できず `KSWIFTK-TYPE-0001`/`KSWIFTK-SEMA-0002` になるコンパイラバグを修正した（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift` の `inferLambdaLiteralExpr` が未解決型パラメータの期待戻り値型をラムダ本体の expectedType に押し下げていたのが原因）。これにより本メモの「`launch { }` 直下の `withLock`/`withPermit` が overload 解決に失敗する」現象および「非コルーチンビルダーからの `withLock` 呼び出しでコンパイラがハングする」現象は解消した（`runBlocking { }` 直下・逐次複数回・値返却いずれも動作、回帰テストは `BundledStdlibExecutionTests` と `Scripts/diff_cases/generic_unit_lambda_inference.kt`）。ただし本ケースは依然コンパイルできない: `launch { }` の trailing lambda 本体から外側可変変数（`counter` 等）をキャプチャする suspend 呼び出し（`mutex.withLock { counter++ }`）を行うと、coroutine lowering がキャプチャ引数を suspend 関数へ転送する経路を未実装で `KSWIFTK-CORO-0003` を返す（`CoroutineLoweringPass+LauncherSupport.swift`、Mutex 無関係の最小コードでも再現する一般的な feature gap = BUG-049）。したがって引き続き SKIP-DIFF とする。
### 解除済み: `channel_basic.kt`

`produce { }` ブロック内の暗黙レシーバ呼び出し（`send(x)` など）が `lowerCallExpr`（暗黙レシーバ経路）を通り、`lowerMemberCallExpr`（明示レシーバ経路）が付与する continuation プレースホルダー引数を受け取れず、`kk_channel_send` に渡る実引数が1個不足して SIGSEGV していた。`CallLowerer.swift` の `lowerCallExpr` 末尾に、`kk_channel_send` / `kk_channel_receive` / `kk_mutex_lock` / `kk_semaphore_acquire` 向けの continuation 0 補完を追加して解決（SKIP-DIFF 解除済み、通常 diff で PASS）。

### 未解除: `coroutine_channels_advanced.kt`

`fun CoroutineScope.produce(from: Int, to: Int): ReceiveChannel<Int>` のような、ユーザー定義の `CoroutineScope` 拡張関数が `runBlocking { }` 直下で暗黙レシーバとして解決できない。`runBlocking` / `launch` / `async` / `coroutineScope` 等のビルダーラムダは現状 `CoroutineScope` を暗黙レシーバ型として保持しないため、拡張関数は明示レシーバでの呼び出しでしか解決しない。

`CoroutineScope` を builder ラムダの `receiver:` として追加する対応を試みたが、クロージャ変換パスの `suspendFunctionArityBySymbol` がレシーバの有無を考慮しておらず、`runBlocking { println("hi") }` のような最も基本的なパターンまで `passed 0 argument(s) but referenced suspend function expects 1` で壊れる重大な回帰を引き起こした。`LambdaLowerer` / `LambdaClosureConversionPass` まで踏み込む必要があり、リスクが高いため撤回済み。`CoroutineScope` インターフェースの型登録と `ReceiveChannel<T>` の `Channel<T>` type alias 登録のみ残している。

### 未解除: `coroutine_flow_backpressure.kt`

4シナリオ全てで `collect { capturedList.add(it) }` / `collectLatest { value -> capturedVar = value }` のように、collector ラムダが外部変数をキャプチャする。調査の過程で以下2件を発見・修正したが、根本原因は残っている。

- **解決済み**: `kk_flow_collect` / `kk_flow_collectLatest` の Runtime ABI が collector の「クロージャ環境ポインタ (closureRaw)」を渡すスロットを持たず、常に `0` (null 環境) で呼び出していたため、collector が外部変数をキャプチャすると値が配信されなかった。`kk_list_map` 等の通常コレクション HOF は `(fnPtr, closureRaw)` のペアを渡す設計なのに対し Flow 側だけこの規約から外れていた。`kk_flow_collect` / `kk_flow_collectLatest` のシグネチャに `collectorEnvPtr` を追加し、`CoroutineLoweringPass+CallRewriting.swift` の `rewriteFlowCollectCall` で `KIRArena.callableValueInfo` から capture 情報を復元して解決。
- **解決済み**: `rewriteFlowCollectCall` の callee ガードが `kk_flow_collect` のみで `kk_flow_collectLatest` を含んでいなかったため、`collectLatest` は書き換えを経由せず、CPS 変換前のラムダシンボル参照がそのまま関数ポインタとして `unsafeBitCast` され SIGSEGV していた。ガードに `kk_flow_collectLatest` を追加して解決。
- **未解決（根本原因）**: `fastProducer()` の `flow { for (i in 1..5) { emit(i); delay(1) } }` のように emitter ブロック内で `delay` を挟むと、`delay` のサスペンド/レジュームが常に `DispatchQueue.global()`（GCD グローバルキュー）上の別スレッドで実行される（`scheduleDelay` / `signalResume` の実装）。一方 `RuntimeFlowCollectContext` は `pthread` のスレッドローカルストレージ（`runtimeFlowCollectStackBox`）で管理されているため、再開後のスレッドではこのスタックが空になり、`kk_flow_emit` が `context == nil` と判定して値を破棄する。結果として、`delay` 前の1回目の emit だけが collector に届く。修正には `RuntimeFlowCollectContext` を `RuntimeContinuationState` のようなスレッドをまたいで伝播する構造に紐付け直す設計変更が必要で、コルーチン全体のスレッドスケジューリングに関わるため対応を見送った。

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

## DEBT-DIFF-005: common stdlib surface gap（解消・分割済み、2026-07-29）

2026-07-29 の棚卸し時点で `.build/debug/kswiftc` が直近コミットに対し stale になっており（`_kk_kclass_create` 等の未解決シンボルで大量の偽 link failure を出していた）、`swift build` で再ビルドしたところ多くのケースが実は既に green だったことが判明した。以降 DEBT-DIFF-005 系の再判定を行う際は、まずローカルバイナリが最新かどうかを疑うこと。

| 領域 | cases | 現状 | 詳細 |
| --- | --- | --- | --- |
| `java.math.BigInteger` | `big_integer.kt` | 解消済み | PR #4667 で `not`/`shiftLeft`/`shiftRight` の未登録とエンディアン不整合バグを修正、SKIP-DIFF 解除済み |
| KSwiftK synthetic Sequence surface | ~~`sequence_takelast.kt`, `sequence_takelastwhile.kt`, `sequence_subtract.kt`~~ | 解消済み（移設） | PR #4660 で JVM kotlinc に無い synthetic surface と確定し、`Scripts/diff_cases` から削除して `CodegenBackendIntegrationTests+Sequence{TakeLast,TakeLastWhile,Subtract}.swift` の candidate-only テストへ移設済み |
| Scope functions | `scope_functions_edge_cases.kt` | 解消済み（2026-07-29 確認） | stale バイナリによる偽 FAIL だった。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| Property delegates | `property_delegate_edge_cases.kt` | **未解消（真のバグ2件、skip 継続）** | `BUG-151`（observable/vetoable コールバック本体の消失）と `BUG-170`（delegate 本体固有の bare-name 複合代入バグ。本 PR のマージ作業中に `origin/master` 側の別バグと3回番号衝突したため 164→168→170 に再採番）。詳細は下記 |
| Regex runtime edge | `regex_runtime_edge_cases.kt` | 解消済み（2026-07-29 確認） | stale バイナリによる偽 FAIL だった。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| ByteArray helpers | `string_tobytearray.kt` | 解消済み（BUG-019 / KSP-660） | `joinToString(sep)` / `contentEquals` は #4671 で合成スタブ化され、SKIP-DIFF 無しで通常 diff を通過。`transform` 付き overload の gap は別課題として BUG-158 に切り出し |
| File/use | `file_use_edge_cases.kt` | 解消済み（2026-07-29 確認） | stale バイナリによる偽 FAIL だった。再ビルド後、通常 diff で green、SKIP-DIFF 解除 |
| Duration/time | `duration_operations.kt`, `experimental_time_edge_cases.kt` | 解消済み（2026-07-29 確認） | 2件とも stale バイナリによる偽 FAIL だった（`experimental_time_edge_cases.kt` の timing-sensitive 懸念は再検証時点では顕在化せず）。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| Math/comparator | `math_trig_functions.kt`, `comparator_composition_edge_cases.kt` | 解消済み（2026-07-29 確認） | 2件とも stale バイナリによる偽 FAIL だった。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| ByteBuffer UUID interop | `uuid_put_uuid.kt` | 解消済み（KSP-508） | `java.nio.ByteBuffer` の最小 bundled 実装を追加し、実 Kotlin 2.4 API の `ByteBuffer.getUuid`/`putUuid` 拡張に置き換えた |
| kotlin.random synthetic overloads | ~~`random_nextfloat_range_overloads.kt`~~ | 解消済み（移設、2026-07-29） | `Random.nextFloat(until)`/`Random.nextFloat(from, until)`（STDLIB-655）は実 kotlinc の `Random` に無い kswiftc 独自拡張と確定（`--force-run-skipped` で reference 側が `too many arguments for 'fun nextFloat(): Float'` で確実に compile error になることを再確認）。PR #4660 と同じ方針で `Scripts/diff_cases` から削除し、`CodegenBackendIntegrationTests+RandomOverloadEdgeCases.swift` の `testCodegenCompilesRandomNextFloatRangeOverloads` へ移設 |
| java.security.SecureRandom synthetic overload | ~~`secure_random.kt`~~ | 解消済み（移設、2026-07-29） | `SecureRandom.getInstance()`（無引数、KSP-467 で意図的に追加した convenience overload）は実 Java/Kotlin が algorithm 引数必須のため JVM reference が原理的に oracle になれないと確定。PR #4660 と同じ方針で `Scripts/diff_cases` から削除し、新設 `CodegenBackendIntegrationTests+SecureRandom.swift` の `testCodegenCompilesSecureRandomNoArgGetInstance` へ移設 |
| `kotlin.text.CASE_INSENSITIVE_ORDER` トップレベル誤登録 | `case_insensitive_order_identity.kt` | 解消済み（BUG-154、`origin/master` #5077） | kswiftc が `CASE_INSENSITIVE_ORDER` を `kotlin.text` トップレベルにも誤登録していた問題を、本 PR のマージ時点で `origin/master` に既に着地していた #5077 が解消。登録経路を top-level property から `String` companion object member（`String.CASE_INSENSITIVE_ORDER`）へ変更し、ケースも書き換えた上で `SKIP-DIFF` を解除済み |

### `property_delegate_edge_cases.kt` 詳細（2026-07-09 調査 → 2026-07-29 再検証）

クラスメンバの `val/var x by lazy {...} / Delegates.observable(...)/vetoable(...)` は、トップレベルプロパティ用の実装（`KIRLoweringDriver+ModuleLowering+PropertyDecl.swift`）とは別系統の実装（`MemberLowerer` / `KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift`）で lowering される。2026-07-09 時点で4件のバグを確認していたが、2026-07-29 に `--force-run-skipped` で再検証したところ状況は以下の通り更新された:

1. **[修正確認済み]** `lowerDelegateAccessor` の delegate ハンドル引数欠落。2026-07-09 時点は「ワークツリーに適用済み、未コミット」だったが、2026-07-29 の再実行で `token`（`lazy` の戻り値）が正しく `"ready"` を返すことを確認し、現行 HEAD で解消済みと確定した。
2. **[修正確認済み]** `emitDelegatePropertyInitializer` が `delegateBody` を参照しない問題。同じく 2026-07-29 の再実行で解消を確認した（`lazy` の初期化ブロック自体は実行され、戻り値も正しい）。
3. **旧課題は BUG-151 に統合**: 2026-07-09 時点では「パラメータ付きトレーリングラムダの `delegateBody` 抽出が AST パーサー層で打ち切られる」という仮説だったが、その後の別セッション（バグバックログ一括対応）の調査で、`observable`/`vetoable`/`notNull` のメンバ委譲は KIR lowering 段階でコールバック本体を丸ごと落とす（`kk_delegate_lambda_NNNN` の body が `return unit` のみになる）ことがより精密に特定され、`BUG-151` として TODO.md に登録済み（未修正、未マージの `devin/1785118661-fix-bug-151` で対応進行中）。旧仮説（AST パーサーの打ち切り）が独立にまだ残っているかは BUG-151 の修正時に再確認が必要。
4. **BUG-168 として再特定**: bare-name（暗黙 `this`）の compound assign（`initCount += 1`）がクラスメンバフィールドへ永続化しない問題。2026-07-09 時点は「delegate と無関係の一般バグ」としていたが、2026-07-29 に `run { n += 1 }` のような通常のクロージャ捕捉で同じパターンを試したところ正しく動作することを確認した — つまり一般的なクロージャ捕捉の compound assign バグは(2026-07-09から今回までの間に)既に解消済みで、`lazy { }` 等の delegate 本体専用の lowering 経路だけがその修正の恩恵を受けていない。delegate 固有の欠陥として当初 `BUG-164` に登録したが、本 PR のマージ作業中に `origin/master` 側で別セッションが独立に「fun interface パラメータへの callable reference 実引数」を BUG-164 として追加済みだったため `BUG-168` に再登録し、さらに別マージで `origin/master` の「lazy()/Lazy<T> 型不一致」の再採番先とも衝突したため最終的に `BUG-170` に登録し直した（2026-07-30）。

`property_delegate_edge_cases.kt` は BUG-151 と BUG-170 の両方が解消するまで SKIP-DIFF を維持する。両バグとも同じ delegate lowering コード領域（`KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift` 等）に触れる可能性が高く、まとめて1つの修正 PR で解消するのが効率的と見込まれる。

## DEBT-DIFF-006: inference / boxed numeric lowering / compiler-plugin API

| cases | 判定 | 次アクション |
| --- | --- | --- |
| `compiler_plugin_api.kt` | implicit-receiver `MutableMap` access type-constraint gap | member access type inference / constraint solving の修正後に通常 diff へ戻す |
| `error_type_inference.kt` | compile-error expectation case | diff harness は現状 stderr parity を厳密比較しないため、diagnostic golden か error-code regression へ移す |

`math_rounding_functions.kt` は 2026-07-09 に解除済み: SKIP-DIFF 追加時点(2026-04-07)は List<Double> の for-loop 変数が boxed pointer のまま round()/roundToInt() 等に渡っていたが、`a553bd1e`「Fix List<Int> for-loop variable unboxing in kotlinc diff regression」(2026-06-10)が型非依存の `kk_unbox_<T>` 挿入(`CollectionLiteralLoweringPass+CallRewriteIteratorBridge.swift` の `appendListIteratorNextWithUnboxing`)を導入した際に List<Double> のケースも副次的に修正されていたが、2026-07-01 の debt 一括整理では未検証のまま残存していた。`--force-run-skipped` で pass を確認し、回帰用の List<Double> ループを `CodegenBackendIntegrationTests+MathEdgeCases.swift` の既存 `testCodegenCompilesMathEdgeCases` に統合した。

## DEBT-DIFF-007: compile-exit parity fix により顕在化した両失敗ケース

`run_case()` は、reference と candidate がともに失敗し同じ非ゼロ終了コードを返しても、無条件に `FAIL` とするよう修正済みである。これにより顕在化したケースのうち、現在75件を原因の個別確認が終わるまで `SKIP-DIFF (DEBT-DIFF-007)` として隔離する。

対象は diagnostic parity、enum/data class/interface/variance、common stdlib・テスト入力、Flow、reflection/metadata、JVM・時間・UUID、finally exception routing に分類する。各ケースのマーカーを起点に、diagnostic golden、実装owner、またはtarget専用runnerのいずれかへ移してからskipを解除する。

## 解除手順

1. 対象ケースだけを `--force-run-skipped` で実行する。

```bash
bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped Scripts/diff_cases/<case>.kt
```

2. reference 側だけが失敗するなら runner / classpath / target 問題として本 inventory を更新する。
3. candidate 側だけが失敗するなら Sema / KIR / Lowering / Runtime owner の task へ分解する。
4. 両者が pass したら `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を削除し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` で通常 diff を確認する。
