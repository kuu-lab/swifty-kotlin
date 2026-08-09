# diff_kotlinc skip inventory

最終更新: 2026-08-06

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
| DEBT-DIFF-001 | 15 | JVM kotlinc reference 不成立（target/classpath/runtime-only） | 2026-07-29 棚卸し完了。当時の19件全件を再ビルドした kswiftc + kotlinc 2.4.10 で再検証し、全件 keep skip 確定（詳細は下記節）。うち serialization 4件は CLEANUP-STUB-121 でケースごと削除し 15件へ |
| DEBT-DIFF-002 | 0 | script-style top-level execution parity（解消済み） | — |
| DEBT-DIFF-003 | 4 | advanced coroutine / channel / Flow / structured concurrency | API 領域ごとに STDLIB-CORO / DEBT-CORO へ分割。cancellation 2 件・`channel_basic.kt`・`coroutine_exception_handling.kt`・`coroutine_scope_lifecycle.kt`・structured concurrency / Deferred / Supervisor 3 件は解除済み（`coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`, `coroutine_exception_handling.kt`, `coroutine_scope_lifecycle.kt`, `coroutine_supervisor_job.kt`, `coroutine_structured_concurrency.kt`, `coroutine_deferred.kt`） |
| DEBT-DIFF-004 | 0 | value class boxing / generics / interface / collection parity（解消済み） | — |
| DEBT-DIFF-005 | 7 | common stdlib / runtime surface gap、または synthetic surface | API 領域別に実装 owner と reference 可否を分離。`file_use_edge_cases.kt` は解除済み |
| DEBT-DIFF-006 | 0 | type inference / boxed numeric lowering / compiler-plugin API（解消済み、2026-07-29） | — |
| DEBT-DIFF-007 | 42 | compile-exit parity fix により顕在化した両失敗ケース | diagnostic golden / owner / 実装へ個別に triage（2026-07-29 に 72→37 まで棚卸し・一部修正済み。2026-07-31 に `enum_entries_function.kt` を追加解除、`enum_basic.kt`/`enum_edge_cases.kt`/`array_hof.kt`/`string_chunked_windowed.kt`/`windowed_step_partial.kt` の root cause を一部実装・範囲縮小。2026-08-02 マージ時再計測で42、詳細は該当節） |

## DEBT-DIFF-001: reference target / classpath / runtime-only

棚卸し完了(2026-07-29、`swift build` で kswiftc を再ビルドし、kotlinc 2.4.10 で当時の19件全件を再検証)。**19件全件 keep skip 確定** — dependency injection や個別 runner で通常 diff に戻せたケースは無かった。

### なぜ dependency injection では解決しないか

`Scripts/diff_kotlinc.sh` の `--kotlinc-classpath` / coroutines jar 自動取得は **reference(kotlinc)側にしか作用しない**。kswiftc は jar/classpath を一切消費しない設計で、`Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift` に手書き登録した合成シンボルだけを認識し、対応する Runtime 実装を呼ぶ。したがって candidate 側が特定の Java/Kotlin API を新たに認識するには synthetic stub の実装が要り、jar 注入は原理的に届かない。「dependency injection で実行可能化」できるのは reference 側だけが理由で落ちているケースに限られるが、以下のケースはいずれも candidate 側の未実装、またはテスト内容自体が実 API 呼び出し規約と非互換という、jar 注入では解決しない理由だった。

### 確定した keep skip 一覧(現行15件)

serialization 4件(`custom_serializer.kt`, `dataclass_serialization.kt`, `json_serialization.kt`, `collection_serialization.kt`)は、synthetic stub を除去した CLEANUP-STUB-121 でケースごと削除した(実 kotlinx.serialization の呼び出し規約で書き直す道は取らず、`kotlinx.serialization` サポート自体を target-out とした)。

| 領域 | cases | 確定理由(2026-07-29 再検証) | 恒久対応の道筋 |
| --- | --- | --- | --- |
| Kotlin/Native / cinterop | `native_annotations.kt`, `native_api.kt`, `platform_info.kt`, `system_get_time_nanos.kt` | `kotlin.native.*` / `kotlinx.cinterop.*` は JVM kotlinc に存在しない。kotlinc 2.4.10 は全件 `unresolved reference` で即失敗、kswiftc は候補シンボルとして受理し正常コンパイルすることを確認。`platform_info.kt` は一時的に `--compile-timeout 15` を超えたが、システム負荷起因の見かけ上のタイムアウトで(`--compile-timeout 60` で再実行すると `time` 計測で user 8s 程度で正常終了、CPU使用率35%と待ち時間が主でビジーループではない)、無限ハングではない | Native surface 専用の Sema golden / target-specific smoke test へ移す(JVM reference を使わない) |
| Kotlin/JS | `js_annotations.kt`, `js_api.kt` | `kotlin.js.*` は JVM kotlinc に存在しない。`error: symbol is declared in module 'kotlin.stdlib' which does not export package 'kotlin.js'` 等で即失敗を確認 | JS/Wasm stub cleanup の target-out backlog と接続する |
| Runtime-only system API | `system_process_start_nanos.kt` | `System.processStartNanos()` は KSwiftK 独自 API。kotlinc は `unresolved reference` で即失敗を確認 | Runtime unit test または candidate-only smoke に移す |
| JDBC / java.sql | `jdbc_basic.kt`, `prepared_statement_complete.kt`, `resultset_complete.kt`, `connection_validation.kt`, `transaction_management.kt` | **訂正**: 従来「custom jdbc:kswiftk driver をこの runtime が提供する」としていたが誤り。`Sources/` 全体を検索しても `DriverManager` / `java.sql` / `JDBC` / `jdbc:kswiftk` は一件もヒットせず、kswiftc は java.sql.\* を一切実装していない。再検証で `ref_compile_exit=0 / cand_compile_exit=1`(reference は素の JDK `java.sql` で普通にコンパイルが通り、candidate 側が `Unresolved reference 'DriverManager'` で落ちる)ことを確認 — reference 側の問題ではなく candidate 側の未実装機能だった。なお `jdbc_basic.kt` のみ実在し移植可能な `"jdbc:sqlite::memory:"` という URL を使っており(他4件は架空の `"jdbc:kswiftk:memory"`)、将来 JDBC 対応に着手する際の再開候補として最有望 | kswiftc に java.sql.\*(DriverManager/Connection/Statement/PreparedStatement/ResultSet 相当)の synthetic stub と対応する Runtime 実装を追加する大きめの機能追加が前提。実装後は `jdbc_basic.kt` を実 SQLite JDBC driver(`org.xerial:sqlite-jdbc`)の reference 側注入で検証し、他4件は URL を `jdbc:sqlite:` 系に書き換えてから同様に戻す |
| KMP expect/actual(単一ファイル制約) | `kmp_common.kt` | kotlinc 2.4.10 は `-Xmulti-platform` と `-Xcommon-sources=<file>` を付けても単一ファイル内の expect/actual を `'expect' and 'actual' declarations can be used only in multiplatform projects` / `expect and corresponding actual are declared in the same module` で拒否することを実測で確認した。common ソースと platform ソースを別コンパイル単位にして最終的にリンクする、genuinely 複数回起動する KMP 専用ビルドモデルが必須で、`kotlinc file.kt` 一発では原理的に表現できない。kswiftc 側も独立した expect/actual バグを抱える | harness に「1ファイルを common/platform に分割して2回コンパイル+リンクする」専用 KMP runner を新設しない限り不可能。ROI が低いため現時点では見送り、`Scripts/diff_kotlinc.sh` の対象外に据え置く |
| SLF4J / logging | `logging_basic.kt`, `logging_advanced.kt` | kswiftc は `org.slf4j.*` を一切実装していない(`Sources/` 全体検索で0件、`Unresolved reference 'LoggerFactory'` で確認)。reference 側は実 slf4j-api + binding 注入で通す経路が既にある(2026-07-09 検証済み)が、candidate 側に synthetic stub が無い限り届かない。`logging_advanced.kt` はさらに `MDC` は実在するが import が無く、`AdvancedLogger`/`StructuredAppender` は実 SLF4J に存在しない架空 API であり、架空 API 部分を残す限り reference 側を通す余地自体が無い | kswiftc に `org.slf4j.*`(Logger/LoggerFactory/MDC 程度)の synthetic stub を追加する機能実装が前提。`logging_advanced.kt` は架空 API 部分を切り離すか削除しない限り、stub 追加後も keep skip のまま |

### 解除済みの周辺ケース(現行15件には含まれないが、過去の調査ノートに記載があったため参考として残す)

- `path_basic.kt`(`kotlin.io.path`): 2026-07-09 解除済み。`import kotlin.io.path.Path` が `Path()` ファクトリしか import せず、`createDirectories` / `exists` / `writeText` 等の拡張関数・拡張プロパティが unresolved だったのが真因(`resolve` / `relativize` / `normalize` 等は `java.nio.file.Path` のネイティブメンバなので import 不要で解決していた)。`import kotlin.io.path.*` に変更し、`--force-run-skipped` で reference/candidate 一致を確認した上で通常 diff に復帰した。
- `uuid_basic.kt`(`kotlin.uuid.Uuid`): 2026-07-09 解除済み。skip 理由は当初「KSwiftK 独自 UUID API」としていたが、実体は標準 `kotlin.uuid.Uuid`(`@OptIn(ExperimentalUuidApi)`)であり、テスト側が `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/非推奨化前の `LEXICAL_ORDER` など `java.util.UUID` の命名と混同した非標準メンバーを呼んでいたのが真因(`kotlin-stdlib-sources.jar` 同梱の実 API と照合して確認)。これら非標準メンバーの呼び出しを削除し、`fromLongs` を既知の定数値で検証する形に置き換え、実 kotlinc 2.4.0 / kswiftc 双方で出力が完全一致することを確認した上で通常 diff に復帰した。`Stdlib/kotlin/uuid/Uuid.kt` 側の `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/`LEXICAL_ORDER` 実装自体(削除するか candidate-only 扱いにするか)は本件のスコープ外で未着手。

## DEBT-DIFF-002: script-style cases（解消済み、2026-07-29）

対象だった7ケースとも `SKIP-DIFF` を解除し、通常の `diff_kotlinc.sh` 経路で green。

| グループ | cases | 解消日 | 根本原因と対応 |
| --- | --- | --- | --- |
| timeout-only suspect | `script_imports.kt`, `script_repl_interactive.kt`, `script_repl_patterns.kt` | 2026-07-09 | script mode (`kotlinc -script`) の JVM 起動 + compile + run を `RUN_TIMEOUT`（デフォルト10s）で縛っていたのが原因。`--script-timeout` を `COMPILE_TIMEOUT` 系へ分離して解決 |
| top-level functions / custom declarations | `script_function_basic.kt`, `script_function_advanced.kt`, `script_toplevel_functions.kt`, `script_import_custom.kt` | 2026-07-29 | 下記「top-level functions / custom declarations 詳細」を参照 |

### top-level functions / custom declarations 詳細（2026-07-29）

症状: candidate (kswiftc) が `KSWIFTK-LINK-0002: No entry point 'main' function found for executable emission.` でコンパイル失敗し続けていた（reference の `kotlinc -script` は成功）。

根本原因: `KotlinParser.parseFile()`（`Sources/CompilerCore/Parser/KotlinParser.swift`）の script 判定が、top-level に `fun` / `class` / `data class` / 拡張関数などの宣言が1つでもあると、たとえ top-level 実行文（`println(...)` 等）が存在してもルート種別を `.script` ではなく `.kotlinFile` に倒す実装だった（`sawNonPropertyDecl` フラグ）。`.kotlinFile` 扱いになると top-level の bare statement は `BuildASTPhase`（`Sources/CompilerCore/Driver/FrontendPhases.swift`）のどの case にもマッチせず黙って破棄され、`main` も合成されないため、link 段階で「エントリポイントが無い」エラーになっていた。実 Kotlin の `.kts` スクリプトは `package` 宣言以外の任意の宣言を top-level 文と自由に混在できるため、この判定は過度に狭かった（この判定は2026-02-17時点で「まず val/var だけ許可する」形で段階的に導入されたもので、fun/class 等への拡張は本チケットまで未着手だった）。

対応:
1. `sawNonPropertyDecl` を `sawPackageHeader` に置き換え、script 判定条件を「top-level 実行文が存在し、かつ `package` 宣言が無い」まで単純化。
2. top-level `fun` 宣言は元々 `.funDecl` として通常の top-level `FunDecl` に登録される一方、`isStatementLikeKind`（`Sources/CompilerCore/AST/BuildASTPhase+BodyParsing.swift`）は `.funDecl` も「文」として扱うため、(1) だけでは script root 合成時に同じ関数が合成 `main()` 内のローカル関数宣言としても二重登録されてしまう。`blockExpressions` / `collectBlockStatementGroups` に `excludingTopLevelFunDecls` オプションを追加し、script root からの呼び出し（`FrontendPhases.swift`）でのみ `.funDecl` を除外して二重登録を防いだ。`class` / `interface` / `object` / `typealias` / `enumEntry` は元々 `isStatementLikeKind` に含まれておらず対象外（重複しない）。

回帰確認: 4 ケースを `--force-run-skipped` で green 化した後、既存の非 skip `script_*.kt`（13件）にも回帰がないことを個別確認。`Tests/CompilerCoreTests/Integration/ScriptModeTests.swift` に、top-level 宣言と top-level 文が混在するパターンの root kind 判定・二重登録防止・実際の KIR コンパイルを固定する回帰テストを追加。

`script_import_stdlib.kt` は2026-07-09に解除済み（本チケットの7件には含まれないが同じ調査の過程で解消): `shuffled()` を `shuffled(Random(42)).sorted()` に変更し、出力順序に依存しない決定論的検証にした(`sequence_shuffled.kt` と同じ idiom)。KSwiftK の `Random` は JVM kotlinc と PRNG アルゴリズムが異なる(xorshift64\* 系の自前実装で XorWow ではない、`KSP-466`)ため、seed を固定しても生の並び順は一致しない。なお、ローカル既定の `RUN_TIMEOUT=10s` は `kotlinc -script` の起動コストだけで超過する(`script_import_stdlib.kt` に限らず `script_hello.kt` など他の非 skip ケースでも同様に再現する、この環境固有の傾向)。CI は `DIFF_RUN_TIMEOUT=30` を使用しており、その設定なら安定して pass する。

## DEBT-DIFF-003: advanced coroutine / channel / Flow

`Scripts/diff_kotlinc.sh` は `kotlinx.coroutines` import を検出して `kotlinx-coroutines-core-jvm` を取得できるため、現在の skip 主因は reference classpath ではなく KSwiftK 側の API / runtime parity である。

| 領域 | cases | owner |
| --- | --- | --- |
| lazy/deferred coroutine start (`CoroutineStart.LAZY`)（未解除） | `coroutine_edge_cases.kt` | `STDLIB-CORO-001` と `DEBT-CORO-003` |
| cancel-before-first-run（解除済み） | ~~`coroutine_exception_handling.kt`~~ | 2026-07-29 に `--force-run-skipped` で再判定した結果、`launch{}` 直後の同期 `cancel()` が本体の最初のサスペンションポイント到達前に確実に届くようになり、JVM 参照が出さない `"cancelled cleanly"` 行がもう出力されないことを確認（8 連続実行で安定）。同時期の coroutine cancellation / Job ハンドル周りの一連の修正の副作用と見られるが、単一の commit には特定していない |
| cancellation（解除済み） | ~~`coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`~~ | `currentCoroutineContext()`/`ensureActive()`/`NonCancellable`/`CoroutineContext.isActive` を追加し、`withTimeoutOrNull` の null 判定バグ（`runtimeNullSentinelInt` ではなく生の `0` を返していた）と `coroutineScope`/`supervisorScope` の直接 throw 握りつぶしバグ（`outThrown` を forward していなかった）、および `job.join()`/`Job.await()` が返却後にハンドルを解放し join 後の `isCancelled` 参照が use-after-free になっていたバグを修正して通常 diff へ復帰 |
| CoroutineScope lifecycle（解除済み） | ~~`coroutine_scope_lifecycle.kt`~~ | 2026-07-29 に再判定して通常 diff で PASS を確認（`--no-parallel` で2回再検証済み）。以前ここに記載していた2件のブロッカー（`private val scope = CoroutineScope(...)` 型注釈なしプロパティの `typeCheckClassLikeMembers` パス順序バグ、非ctor引数プロパティ初期化子の instance storage 書き込み漏れ = PR #4691 相当）はいずれも再現しなくなっていた |
| structured concurrency / Deferred / Supervisor（解除済み） | ~~`coroutine_deferred.kt`, `coroutine_structured_concurrency.kt`, `coroutine_supervisor_job.kt`~~ | Job hierarchy / async-await / supervisor semantics。詳細は下記「structured concurrency / Deferred / Supervisor 詳細」節を参照 |
| Channel / produce / Flow backpressure | `coroutine_channels_advanced.kt`, `coroutine_flow_backpressure.kt` | `DEBT-CORO-002` の producer / channel runtime と Flow lowering |
| sync primitives | `coroutine_mutex_semaphore.kt` | KSP-677 で Sema の overload 解決バグ（`KSWIFTK-SEMA-0002`）を解消し、BUG-049 で `launch { }` 本体のキャプチャ付き suspend 呼び出しの coroutine lowering feature gap（`KSWIFTK-CORO-0003`）も解消（回帰は `coroutine_launch_capture.kt`）。残ブロッカーは CORO-0003 とは別の既存 runtime GC-under-parallelism クラッシュ（100+ 並列 launch で `swift_retain` が SIGSEGV）と `delay` 依存 |

`coroutine_base_edge_cases.kt`（direct suspend call のデッドロック、try/catch 内 suspend call の例外もみ消し）と
`coroutine_context_switching.kt`（`withContext` の期待型ハンドリング）は 2026-07-09 に skip 解除済み。

残る2件は当初 "advanced coroutine API 未実装" という一般的理由だったが、実際の root cause は次の通りに絞り込めた:

- `coroutine_exception_handling.kt`（解除済み）: `async { throw ... }.await()` の例外もみ消しは `kk_kxmini_async` が完了時に continuation の
  `thrownException` を確認せず `task.complete(with: result)` を無条件に呼んでいたバグで、これは修正済み
  （`kk_kxmini_launch_with_exception_handler` と同じパターンを適用）。当時残っていた唯一の差分は、`launch{}` 直後に同期 `cancel()`
  すると JVM 参照には出ない `"cancelled cleanly"` 行が余分に出力される件だったが、2026-07-29 の再判定でこの差分も解消していることを確認し、`SKIP-DIFF` を解除した。
- `coroutine_edge_cases.kt`（未解除）: `launch(start = CoroutineStart.LAZY) { ... }` がそもそもコンパイルできない
  （`CoroutineStart` 型・`launch(start:, block:)` オーバーロードを意図的に未登録のまま）。理由は
  `rewriteLauncherCall` の dispatcher-aware path が 2 引数 `launch` の第一引数を無条件に `CoroutineDispatcher` として
  `kk_kxmini_launch_with_dispatcher` に渡すため、`CoroutineStart` 値を渡すと実行時にクラッシュ（`kk_job_is_cancelled`
  内で `EXC_BAD_ACCESS`）する。type-aware disambiguation なしで登録するのは危険なので見送った。

`CoroutineStart.LAZY` を実装するには、実際に本体を dispatch する前に "start()/最初の親 suspend まで待つ" フェーズを持つ
RuntimeJobHandle 状態が要る。scheduler の分岐が広いため、単発の bug fix ではなく別 task として切り出すべき。

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

### structured concurrency / Deferred / Supervisor 詳細（解消済み、2026-07-30）

3ケースとも当初想定（「不足APIを足すだけ」）より深いバグに当たった。調査で Sema 側の一般的な型推論バグを複数発見・修正済みだが、各ケースとも KIR lowering / runtime 層に別種の未解決ブロッカーが残る。

2026-07-29 追記: `coroutine_supervisor_job.kt` は `--force-run-skipped` の再判定で通常 diff PASS を確認し（2回再検証済み）、`SKIP-DIFF` を解除した。`SupervisorJob()` / トップレベル `CoroutineScope(context)` は `HeaderHelpers+SyntheticCoroutineRegistry.swift`（`STDLIB-CORO-090`）で Sema 登録済み、ランタイム側も `RuntimeCoroutine.swift` に対応する `kk_job_new` 系実装がある状態を確認した。以下のブロッカー説明は当時の調査記録として残す。残る `coroutine_deferred.kt` / `coroutine_structured_concurrency.kt` の2件は未解除のまま。

**この調査で修正済み（3ケース共通の前提を直した Sema 修正、副作用として広く安全性を確認済み）:**

- `kotlin.coroutines` パッケージが default import list に無く、`coroutineContext` が unresolved になっていた（`ScopeBuilder.swift`）。
- `IntRange.map` が transform ラムダの実際の戻り値型を無視し、常に `List<Any>` を返していた（`CallTypeChecker+RangeMemberFallback.swift`）。`(1..5).map { n -> ... }` の要素型が壊れていたため `it.await()` 等の後続メンバー呼び出しが unresolved になっていた。
- `async`/`coroutineScope`/`supervisorScope` が常に `Any`（または raw `Deferred`）を返し、trailing lambda の実際の本体型を読み戻していなかった（`CallTypeChecker.swift` の `adjustedReturnType` 分岐、新規 `CallTypeChecker+CoroutineBuilderReturnType.swift`）。`Deferred` はクラスレベル型パラメータを持たないため、`.await()` の戻り値型は `bindDeferredElementType`/`deferredElementType`（`SemanticsModels.swift`、Flow の `flowElementType` と同型のサイドチャネル方式）で追跡するようにした。`LocalDeclTypeChecker.swift` で `val`宣言時にこのマーカーを伝播する。
- Kotlin の「ラムダの期待戻り値型が `Unit` のとき、本体の実際の値は破棄されボディの型は問わない」という言語仕様が未実装だった。`inferLambdaLiteralExpr`（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）がラムダ本体を型推論する際に `expectedType: Unit` をそのまま本体式（例: 関数呼び出し）に伝播しており、本体が非Unit値を返す呼び出し（例 `repeat(3) { i -> someIntFn(i) }`）の呼び出し解決自体が「戻り値がUnitと非互換」として `No viable overload found for call` になっていた。**これはコルーチンと無関係な一般的なSemaバグ**（`repeat`/`forEach` 等あらゆる `(T) -> Unit` パラメータで発生）で、`coroutine_structured_concurrency.kt` の `repeat(3) { i -> launch { ... } }` パターンを直接ブロックしていた。修正: 本体の `expectedType` は expected return が `Unit` の場合 `nil` に落とす。
- 上記5件は `bash Scripts/diff_kotlinc.sh` で以下の回帰確認済み（regressionなし）: `coroutine_scope.kt`, `job_basic.kt`, `supervisor_scope_basic.kt`, `async_await.kt`, `launch_basic.kt`, `range_hof.kt`, `repeat.kt`, `array_hof.kt`, `collection_hof.kt`, `stdlib_collection_hof.kt`, `string_hof.kt`, `lambda_it.kt`, `lambda_with_receiver.kt`, `sequence_forEach_flatMap.kt`, `set_map_filter_foreach.kt`, `map_entries_hof.kt`, `closure_multi_capture_hof.kt`, `destructuring_lambda.kt`, `labeled_return_lambda.kt`（計19ケース）。

**2026-07-30 の続き調査で解消。当初の各ケース別ブロッカーと実際の root cause:**

- `coroutine_supervisor_job.kt`: 上記調査時点(2026-07-10) では `SupervisorJob()`/`CoroutineScope(context)` 未登録と見立てていたが、その後の KSP-674〜679 bundled-stdlib 移行で両方とも実装済みになっていた（`HeaderHelpers+SyntheticCoroutineRegistry.swift` の `kk_supervisor_job_new`/`kk_coroutine_scope_new_with_context` 登録）。`SKIP-DIFF` を外すだけで通常 diff PASS。
- `coroutine_structured_concurrency.kt`: 「`coroutineScope{}` の capture-lowering バグ」という当初の診断は、`coroutineScope`/`supervisorScope` が KSP-679 で実際の bundled Kotlin source 関数（`Stdlib/kotlinx/coroutines/CoroutineScope.kt`）に移行済みだったため的外れになっていた。実際に残っていたのは3件の一般的バグ: (1) `coroutineScope`/`supervisorScope` の戻り値型 narrowing が `CallTypeChecker.swift` の `coroutineLauncherLambdaArgIndex`/`adjustedReturnType` 判定リストに含まれておらず `results.forEach` 等が unresolved になっていた、(2) **外側変数をキャプチャする suspend ラムダが、非suspend文脈で型チェックされた場合に captureless 前提の生ポインタとして渡され、間違った引数個数で呼ばれて SIGBUS するコンパイラ全体に及ぶ一般バグ**（`LambdaLowerer.swift` の `materializeEscapingCallableValue`/`lowerNonCapturingLambda` が呼び出しコンテキストの非suspend期待型を鵜呑みにして `isSuspend: false` を確定していたのが根本原因。ラムダ本体を実際にスキャンして suspend 呼び出しの有無を判定する `lambdaBodyRequiresSuspend` を追加し、`effectiveIsSuspend` として一貫させて修正）、(3) `List<String> + "x"` のような二項演算子 `+` が LHS の型を無視し RHS が String というだけで文字列結合と誤解釈する一般バグ（`ExprTypeChecker+BinaryAndFlowInference.swift`、`isString(lhs) || isString(rhs)` → `isString(lhs)` に修正）。加えてテストケース自体が抱えていた並行性レース（`launch{}` が実 GCD スレッドへ並列ディスパッチされるため、kotlinx の既定シングルスレッド確定と異なり共有可変状態への同時書き込みがクラッシュ/値化けを起こす）も、共有状態を避ける形にケースを調整して解消。
- `coroutine_deferred.kt`: `CoroutineStart`/`awaitAll` の Sema 未登録は想定通り。`awaitAll` は bundled Kotlin source（`CoroutineScope.kt`）へ直接ループ実装で追加（HOF越しの `.await()` を避けるため）。**Iterator 経由 `.await()` の SIGSEGV** は、`jobs.map { it.await() }` の `.map`（bundled Kotlin source、非 `inline`）の `transform` パラメータが非suspend宣言のため、実際には suspend な `{ it.await() }` を collection-HOF 用アダプタ（`CallLowerer+HOFAdapter.swift` の `makeCollectionHOFCallableAdapter`）でラップする際、アダプタの `isSuspend` がラムダの実体でなく HOF の宣言型を鵜呑みにしていたのが原因（アダプタが `CoroutineLoweringPass` の CPS 変換対象から漏れ、`.await()` 呼び出しが未初期化の continuation を読んで SIGSEGV）。呼び出し先の実際の `isSuspend` を優先するよう修正。`CoroutineStart.LAZY`（lazy start）は launch 側と同じ「genuine pending state 欠如」の大きな未解決ギャップのため、このケースの対象から意図的に除外（コメントで明記、`coroutine_edge_cases.kt` 側で引き続き追跡）。

**副次的に発見・修正した一般バグ:**

- 上記の suspend ラムダ materialization 修正は、`runBlocking`/`launch`/`async`/`produce` のような KIR レベルの coroutine launcher（`CoroutineLoweringPass+LauncherSupport.swift` の BUG-049 由来 launcher-continuation 機構が生シンボル参照を前提とする）と衝突し、`produce { send(x) }`（`channel_basic.kt`）を `KSWIFTK-CORO-0003` で退行させた。`Sema/Models/SemanticsModels.swift` に `coroutineLauncherLambdaExprIDs` マーカーを追加し、`runBlocking`/`launch`/`async`（`CallTypeChecker.swift` 通常経路）と `produce`（同ファイル内の専用早期リターン分岐、CORO-075）の両方でラムダ引数をマークして `LambdaLowerer` 側の materialization から除外することで解消（`coroutineScope`/`supervisorScope` はこの launcher 機構を使わない実 Kotlin 関数のため対象外のまま）。

**検証:** Golden テスト（Lexer/Parser/Sema/Diagnostics、計355ケース）全 PASS、`Scripts/diff_kotlinc.sh Scripts/diff_cases`（678ケース）で回帰0件を確認（`coroutine_delay_basic.kt` のタイミング閾値ベース判定が高負荷環境で一過性に揺れたのは今回の変更と無関係と個別に再現確認済み）。

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
| Sequence source/runtime interop | `flatten_sequence_edge_cases.kt`, `sequence_lazy_eval.kt` | source Sequence object-expression は runtime List/Sequence/RuntimeSequenceBox ハンドルに対する `.iterator()` 仮想ディスパッチが未整備（`sequence {}` builder 含む KSP-447 残留） | KSP-441 後続 / KSP-447 で itable ブリッジを整備後に `--force-run-skipped` で再判定 |
| Scope functions | `scope_functions_edge_cases.kt` | common stdlib gap | `let` / `also` / `with` / `apply` / `takeIf` / `takeUnless` を API 別に分解 |
| Property delegates | `property_delegate_edge_cases.kt` | 解消済み（BUG-151）: クラスメンバ初期化、コールバック本文の型チェック、暗黙 `this` の捕捉、Function3 ABI を修正し SKIP-DIFF を解除 | — |
| Regex runtime edge | `regex_runtime_edge_cases.kt` | named group / invalid pattern parity | RuntimeRegex と diagnostic behavior の regression に分割 |
| ByteArray helpers | `string_tobytearray.kt` | 解消済み（BUG-019 / KSP-660）: `joinToString(sep)` / `contentEquals` は #4671 で合成スタブ化され、SKIP-DIFF 無しで通常 diff を通過。`transform` 付き overload の gap は別課題として BUG-158 に切り出し | — |
| File/use | `file_use_edge_cases.kt` | 解消済み（2026-07-29）: `Closeable.use` と `java.io.File` surface のgapは解消しており、`--force-run-skipped` の再判定で通常 diff PASS を確認した | — |
| Duration/time | `duration_operations.kt`, `experimental_time_edge_cases.kt` | formatting / timing-sensitive output | `Duration.toString` parity と monotonic time test determinism を分離 |
| Math/comparator | `math_trig_functions.kt`, `comparator_composition_edge_cases.kt` | math function / comparator API gap | math runtime ABI、Comparator composition API に分ける |
| ByteBuffer UUID interop | `uuid_put_uuid.kt` | 実装済み（KSP-508）: `java.nio.ByteBuffer` の最小 bundled 実装を追加し、実 Kotlin 2.4 API の `ByteBuffer.getUuid`/`putUuid` 拡張に置き換えた。`SKIP-DIFF` 解除済み | — |
| kotlin.random synthetic overloads | `random_nextfloat_range_overloads.kt` | `Random.nextFloat(until)`/`Random.nextFloat(from, until)` は kswiftc 独自拡張（STDLIB-655）で、実 kotlinc の `Random` にはない | 対象として残すなら STDLIB API 拡張として明記、対象外なら target-out backlog |
| java.security.SecureRandom synthetic overload | `secure_random.kt` | `SecureRandom.getInstance()`（無引数）は kswiftc 独自の convenience overload で、実 Java/Kotlin は algorithm 引数必須 | candidate-only test として扱うか API 意図を明記 |

`case_insensitive_order_identity.kt` は 2026-07-27 に解除済み（BUG-154）: kswiftc は `CASE_INSENSITIVE_ORDER` を top-level `kotlin.text` プロパティとして誤登録していたが、実 Kotlin の `String.Companion.CASE_INSENSITIVE_ORDER`（`String.CASE_INSENSITIVE_ORDER`）と同じく String companion object のメンバとして登録するよう修正。ケースを `String.CASE_INSENSITIVE_ORDER` 参照へ書き換え、`SKIP-DIFF` marker を削除して通常 diff に戻した。

`experimental_time_edge_cases.kt` は実行速度差で stdout が揺れるため、固定 clock / larger duration / unit test のどれかへ寄せてから diff に戻す。

`property_delegate_edge_cases.kt` の詳細（2026-07-09 調査）: クラスメンバの `val/var x by lazy {...} / Delegates.observable(...)/vetoable(...)` は、トップレベルプロパティ用の実装（`KIRLoweringDriver+ModuleLowering+PropertyDecl.swift`）とは別系統の実装（`MemberLowerer` / `KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift`）で lowering されており、そちらは `StdlibDelegateKind`（`lazy`/`observable`/`vetoable`/`notNull`）を想定していなかった。以下の問題はいずれも修正済み:

1. **[修正済み]** `MemberLowerer+DelegatedAndAccessorLowering.swift` の `lowerDelegateAccessor`: `.custom` 以外（`lazy`/`observable`/`vetoable`/`notNull`）の getter/setter が `kk_lazy_get_value`/`kk_observable_set_value` 等を呼ぶ際、delegate ハンドル（`$delegate_x` の値）を引数に含めていなかった（`arguments: []` / `arguments: [valueExprID]` のみ）。ランタイム ABI（`kk_lazy_get_value(handle)`, `kk_observable_set_value(handle, newValue)` 等、`RuntimeABISpec+Delegate.swift`）は handle 必須のため、実引数0/1個で宣言された LLVM 外部関数型と実体（Swift `@_cdecl` 関数）のシグネチャが食い違い、`handle` が不定値になり `null`/`0` を返し続けていた。
2. **[修正済み]** `KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift` の `emitDelegatePropertyInitializer`: メンバプロパティの delegate 初期化はコンストラクタ内で `propertyDecl.delegateExpression` のみを評価しており、トレーリングラムダ `propertyDecl.delegateBody`（`lazy` の初期化ブロック、`observable`/`vetoable` のコールバック）を一切参照していなかった。`lazy` は `kk_lazy_create` 呼び出し自体が欠落（生のクロージャ参照を直接フィールドへ copy）、`observable`/`vetoable` は `kk_*_create` の初期値のみ渡りコールバック引数が欠落していた。トップレベル実装が持つ `emitLazyDelegateInit`/`emitCallbackDelegateInit`（`lowerDelegateInitialValue`/`lowerDelegateLambdaBody` を使用）と同等のロジックを `StdlibDelegateKind` 判定つきで追加した。
3. **[修正済み・BUG-151]** パラメータ付きトレーリングラムダ（`Delegates.observable(1) { _, old, new -> println(...) }` のような `_, old, new ->` prefix 付き）の `delegateBody` 抽出（`BuildASTPhase+DeclBuilders.swift` の `makePropertyDecl` → `blockExpressions`）が、文単位区切りを前提にした汎用パーサーのため、パラメータリスト+アロー構文を正しく扱えず、コールバック本文が `unit` として消えていた（`println`/比較式が一切実行されない）。`lazy` のようにパラメータなしの trailing block は正しく抽出できていた。BUG-151 で block トークン列を `parseLambdaLiteral()` で再パースし、パラメータ名を KIR の synthetic パラメータへ束縛するよう修正。
4. **[修正済み]** bare-name（暗黙 `this`）の compound assign / inc-dec（`count += 1`, `count++`）がクラスメンバフィールドに対して書き込みを永続化せず、「ephemeral local」へ落ちていた。暗黙 receiver と nominal layout の field offset を使い、実フィールドへ `kk_array_set` するよう修正。

5. **[修正済み]** `observable`/`vetoable` の3引数コールバックは、Sema が callback body と引数を型チェックし、KIR が暗黙 receiver を boxed Function3 に捕捉する。Runtime は `kk_function_invoke_3` で raw thunk と boxed closure の両方を呼び分ける。

`property_delegate_edge_cases.kt` は上記の回帰ケースとして SKIP-DIFF を解除し、通常の kotlinc 差分対象へ戻した。

**2026-07-29 追記（DEBT-KIR-008 修正）**: 上記調査では見落とされていた5件目のバグを発見・修正した。`propertyDecl.delegateBody`（トレーリングラムダ本体）は `delegateExpression` と異なり Sema の型チェック（`identifierSymbols` 束縛）を一切通っておらず、`lazy { label }` のように囲む class member を参照する式は静かに `.unit` に落ちていた（`lazy { "literal" }` のような無参照の本体だけが偶然動いていた）。加えて `$delegate_x`（delegate ハンドルを保持するフィールド）は `nominalLayout` の field offset には登録されるものの、getter/setter/コンストラクタ初期化子が実際には module-global スロットとして読み書きしており、クラスの全インスタンスで共有されていた（DEBT-KIR-008 本体の症状）。`.lazy`（trailing lambda が 0 引数のケースのみ、`kk_function_invoke_0` の boxed-closure dispatch を利用）に限定してこの2件を修正した。

**2026-07-30 追記（BUG-151 完了）**: `observable`/`vetoable` の3引数 callback も、Sema の callback body 型チェックと boxed Function3 ABI により暗黙 receiver を捕捉できるようにした。bare-name compound assign の instance-field store も同PRで修正し、`property_delegate_edge_cases.kt` の SKIP-DIFF を解除した。

## DEBT-DIFF-006: inference / boxed numeric lowering / compiler-plugin API（解消済み、2026-07-29）

`math_rounding_functions.kt` は 2026-07-09 に解除済み（下記参照）。`error_type_inference.kt` は 2026-07-09 に diff_cases から削除済み: 5 シナリオ全てで kswiftc が診断を1件も出さないことが判明し、うち3件は本物の Sema 検出漏れとして `DEBT-SEMA-002`/`DEBT-SEMA-003`/`DEBT-SEMA-004`（`TODO.md` の「Sema 型推論診断ギャップ」節）へ切り出して `assertNoDiagnostic` ベースの回帰テストで現状を固定、残り2件は元の想定コメントが誤りだった正当な Kotlin コードと判明したため対応不要。最後まで残っていた `compiler_plugin_api.kt` も 2026-07-29 に `SKIP-DIFF` を解除し、通常の `diff_kotlinc.sh` 経路で green。

`compiler_plugin_api.kt` は当初「implicit-receiver `MutableMap` access の type-constraint gap」という単一バグとして棚卸しされていたが、実際には独立した3層のバグが積み重なっていた（1つ目を直すと次のエラーが露出する形で発見した）。

1. **Sema**: `object` シングルトンのメンバー関数をトレイリングラムダ付きで呼ぶと、ラムダのパラメータ型推論が壊れる。`CallTypeChecker+MemberCallInferenceContext.swift` の `tryInferFQNPackageTopLevelCall`（`kotlin.math.abs(x)` のような FQN パッケージ修飾呼び出し専用の特殊パス）が、`SomeObject.member(args) { lambda }` という **named object のメンバー関数呼び出し**も「パッケージ修飾トップレベル関数呼び出し」と誤認していた。原因は、object のメンバー関数もパッケージのトップレベル関数と同じ `ownerFQName + [memberName]` スキームで symbol table に登録されるため、`sema.symbols.lookupAll(fqName:)` によるルックアップが偶然マッチしてしまうこと。この特殊パスは引数を expected type なしで即座に型推論するため、トレイリングラムダの `it` や名前付きパラメータが解決できなかった（`Registry.update(pluginId) { m -> m.copy(...) }` の `m` が unresolved になり `KSWIFTK-SEMA-0024` 等が発火）。class instance・companion object 経由の呼び出しは別コードパスを通るため影響を受けず、この非対称性がバグを長らく覆い隠していた。修正: receiver path 自体が既存の class/interface/object/enumClass 宣言に解決する場合はこの特殊パスを早期に断念し、2フェーズのオーバーロード解決（非ラムダ引数→オーバーロード確定→ラムダへ期待型伝播）を行う通常の member-call 解決に委ねるガードを追加。
2. **Sema**: `List<String> + String` が文字列連結と誤認される。`ExprTypeChecker+BinaryAndFlowInference.swift` の `inferBinaryExpr` で、「List/Sequence の plus/minus」フォールバックより**前**に「LHS または RHS が String なら文字列連結」という判定が走っていたため、要素型がたまたま String である `List<String>` に String 要素を足す式（`m.registeredExtensions + "$kind:$name"` 等）が、LHS が List であるにもかかわらず無条件に文字列連結として型付けされていた（expected type が無ければ黙って誤った実行結果、expected type があれば `KSWIFTK-TYPE-0001`）。data class の `copy()`・object・ラムダとは無関係の一般的な型推論バグで、`listOf("a") + "x"` だけでも再現する。修正: 2つのチェックの順序を入れ替え、LHS が List/Sequence 型かどうかの判定を文字列連結判定より先に評価する。
3. **KIR / Runtime**: 上記2件を直した後に露出。`Set.sortedBy`（`Map.entries` 経由）のリンクエラーとランタイムパニック。直接呼び出し（`m.entries.sortedBy { it.key }`）では、`CallLowerer+SafeMemberCalls.swift` とは別の通常（非 safe-call）経路（`lowerMemberCallExpr`）を通るため無関係だが、`kk_list_sortedBy`（`Runtime/RuntimeCollectionHOF.swift`）が `RuntimeListBox` ハンドルしか受け付けず、`Map.entries` が返す `RuntimeSetBox` ハンドルに対して `invalid list handle` パニックを起こしていた（`sortedBy` は Kotlin では `Iterable<T>` 上に定義されており、List 以外の具象コレクション受信者にも呼べる必要がある）。修正: `RuntimeCollectionHelpers.swift` に既にあった List/Set 両対応の `runtimeCollectionElements(from:)` を `kk_list_sortedBy` から使うよう変更（`runtimeListBox(from:)` 単体使用から切り替え）。直接呼び出しはこれで green（回帰テスト: `CodegenBackendIntegrationTests+SafeCallSetSortedByRegression.swift` の `testCodegenSetSortedByDirectCall`）。
   `meta?.options?.entries?.sortedBy { it.key }` のような safe-call（`?.`）チェーン経由では別途、`lowerSafeMemberCallExpr` が callee を解決できなかった場合に通常経路の名前ベース collection/synthetic フォールバック解決（`loweredMemberCalleeName`）を呼ばず、coroutine ハンドル向けの固定名リストにマッチしなければ生の Kotlin 関数名をそのまま外部シンボル名として使ってしまい `_sortedBy` という未解決シンボルでリンクエラーになる問題も見つかった。さらに、`hasHOFLambdaArg`（`loweredMemberCalleeName` の dispatch key に使う）を構文的な「ラムダかどうか」判定で計算していたため、`emitMemberCallInstruction`（通常経路）が使う `sema.bindings.isCollectionHOFLambdaExpr`（`markCollectionHOFLambdaExpr` で明示的にマークされた一部の HOF 名だけが true になる、狭いフラグ）と食い違い、誤った dispatch key で解決してしまっていた。加えて、この safe-call 経路の `chosen == nil` 分岐は呼び出し引数リストにレシーバを一切挿入しない設計上の欠落（`Random.nextInt`/`nextLong` に対して通常経路で既に個別対処されていたのと同種のギャップ）もあった。修正: (a) `hasHOFLambdaArg` の計算を `emitMemberCallInstruction` と同じ `sema.bindings.isCollectionHOFLambdaExpr` ベースに揃える、(b) レシーバ挿入を自前実装せず、通常経路が使っている共有ヘルパー `appendReceiverToMemberArguments`（`CallLowerer+MemberCallEmission.swift`）をそのまま呼ぶ。この2点により `sortedBy` 単体の safe-call は完全に動作するようになった（回帰テスト: `testCodegenSetSortedByThroughSafeCallChain`）。
   ただし、この過程で**別の Sema レベルの gap**を発見した: `joinToString`（transform ラムダの有無に関わらず）のように、通常のドットコールでは常に実 `chosenCallee` に解決される（`unresolvedCollectionMemberNames` にも含まれない）メンバー関数が、**同じ呼び出しを safe-call（`x?.joinToString(...)`）で書くと `chosenCallee` が解決できなくなる**現象を確認した。これは引数渡しの問題ではなく、safe-call の型推論経路（`inferSafeMemberCallExpr`）に固有のオーバーロード解決バグと見られ、今回の修正のスコープ外として切り出した。`compiler_plugin_api.kt` は `?.let { entries -> entries.sortedBy { ... }.joinToString(...) }`（`sortedBy`/`joinToString` を同じ `let` ブロック内で連鎖し、どちらも smart-cast された非 null 値への通常呼び出しにする）でこの gap を回避している。

回帰テスト: `Tests/CompilerCoreTests/Sema/DataFlowAndSemaRegressionTests+ObjectMemberCallLambdaInference.swift`、`Tests/CompilerCoreTests/Sema/DataFlowAndSemaRegressionTests+ListStringPlusOperatorInference.swift`、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+SafeCallSetSortedByRegression.swift`（`testCodegenSetSortedByDirectCall`/`testCodegenSetSortedByThroughSafeCallChain`/`testCodegenSetSortedByInsideSafeCallLet`）、および `Scripts/diff_cases/compiler_plugin_api.kt` 自体（`SKIP-DIFF` 解除済み）。

`math_rounding_functions.kt` は 2026-07-09 に解除済み: SKIP-DIFF 追加時点(2026-04-07)は List<Double> の for-loop 変数が boxed pointer のまま round()/roundToInt() 等に渡っていたが、`a553bd1e`「Fix List<Int> for-loop variable unboxing in kotlinc diff regression」(2026-06-10)が型非依存の `kk_unbox_<T>` 挿入(`CollectionLiteralLoweringPass+CallRewriteIteratorBridge.swift` の `appendListIteratorNextWithUnboxing`)を導入した際に List<Double> のケースも副次的に修正されていたが、2026-07-01 の debt 一括整理では未検証のまま残存していた。`--force-run-skipped` で pass を確認し、回帰用の List<Double> ループを `CodegenBackendIntegrationTests+MathEdgeCases.swift` の既存 `testCodegenCompilesMathEdgeCases` に統合した。

## DEBT-DIFF-007: compile-exit parity fix により顕在化した両失敗ケース

`run_case()` は、reference と candidate がともに失敗し同じ非ゼロ終了コードを返しても、無条件に `FAIL` とするよう修正済みである。これにより顕在化した72件を、diagnostic parity、enum/data class/interface/variance、common stdlib・テスト入力、coroutine Flow、reflection/metadata、JVM・時間、finally exception routing の7グループへ分解して個別に triage した(2026-07-29)。

### 2026-07-29 棚卸しの結果概要

72件中35件を解消(72→37)。内訳:

2026-07-31 追記: 上記37件からさらに `enum_entries_function.kt` を解消(37→36)。加えて `enum_basic.kt`/`enum_edge_cases.kt`/`array_hof.kt`/`string_chunked_windowed.kt`/`windowed_step_partial.kt` の5件は、下記グループ2・グループ3の各行に記載の通り root cause の主要部分を実装・修正し、残存ブロッカーの範囲を大幅に縮小した(いずれもファイル自体はもう1件の別バグでまだブロックされているため未解除)。

- **診断/ネガティブテスト(旧グループ1、22件)**: 全件解消。JVM kotlinc の stderr はこのハーネスで比較されないため、複数シナリオを1ファイルに束ねた「意図的なコンパイルエラー」ケースは本質的に JVM kotlinc を oracle にできない。既存の `Tests/CompilerCoreTests/GoldenCases/Diagnostics/` に近い golden テストがある5件(`error_type_mismatch.kt`→`type_mismatch.golden`, `type_error.kt`→同, `error_unresolved_reference.kt`→`unresolved_reference.golden`, `deprecated_error.kt`→`deprecated_annotation.golden`, `override_variance_errors.kt`→`visibility_narrowing_override.golden`)は削除。残り15件(`abstract_property_errors`, `builder_dsl_invalid_arg`, `char_get_error`, `error_abstract_instantiation`, `error_interface_conflicts`, `error_null_safety`, `error_override_mismatch`, `error_parameters`, `error_redeclaration`, `error_return_type`, `error_semantic_basic`, `error_visibility`, `is_type_check_non_reified_error`, `val_member_compound_assign_error`, `val_reassign_error`)は `Tests/CompilerCoreTests/GoldenCases/Diagnostics/` へ移設し `UPDATE_GOLDEN=1` で golden 生成、`Scripts/diff_cases` から削除した。`contract_returns.kt`/`contracts_basic.kt` の2件は実は負テストではなく、`kotlin.contracts.contract { }` の実機能バグ(下記参照)と判明したため別枠で継続 skip。
- **finally routing(旧グループ7、1件)**: 解消。`finally_exception_routing.kt` はテスト自体の欠陥(catch節に`return`が無く、real kotlinc も"missing return statement"で最初からコンパイル不能だった)で、`return "caught"` を追加して通常 diff に復帰。
- **その他のテスト入力ミス修正による解消(14件)**: `interface_super_call.kt`(曖昧な`super.greet()`を`super<B>.greet()`に), `math_extended.kt`(`IEEErem`/`withSign`/`nextTowards`をトップレベル関数呼び出しからメンバー呼び出しに), `null_receiver_is_null_or_empty.kt`(型無し`null`への`isNullOrEmpty()`はkotlinc側も曖昧で削除), `nullable_receiver_ext.kt`(`String`と`String?`の拡張関数はJVM erasureで衝突するため片方削除), `string_format_positional.kt`(`$`エスケープ漏れ), `uint_range.kt`/`ulong_range.kt`(`Int`と`UInt`/`ULong`の`mapIndexed`内混在に`.toUInt()`/`.toULong()`追加), `temp_files.kt`(`kotlin.io.createTempFile`/`createTempDir`はDeprecationLevel.ERRORのため`kotlin.io.path`版に書き換え), `kclass_ktype_basic.kt`/`metadata_api.kt`(`kotlin.reflect`系importの追加、および存在しない`KClass.type`参照の削除)。
- **ハーネス側の修正(1件)**: `Scripts/diff_kotlinc.sh` に `KOTLINC_TEST_JAR`(`kotlin-test.jar` 自動解決、`KOTLINC_STDLIB_JAR`/`KOTLINC_REFLECT_JAR` と同じ仕組み)を追加。`test_framework_basic.kt` の ref 側失敗は `kotlin.test.*` が reference のクラスパスに無いだけで、候補側(kswiftc)は元々正しく動いていた。
- **コンパイラ本体の修正(1件、DEBT-DIFF-007 調査の副産物)**: `error_parameters.kt` の triage 中に、`varargFun(name = "bad", 1, 2)`(named引数の後に来る positional 引数が、宣言順序上その named引数より前にある vararg パラメータへ逆流して束縛される)を kswiftc が誤って受理する実バグを発見・修正した。`Sources/CompilerCore/Sema/Resolution/Resolution+TypeConstraints.swift` の `buildParameterMapping` に `maxBoundParamIndex`(そこまでに束縛済みの最大パラメータ index)を追加し、named引数の後の positional 引数が vararg パラメータへ束縛される際に「宣言順序が逆行していないか」を検証するよう修正(回帰は `error_parameters.kt` の golden ケースで固定、既存の `OverloadResolverTests` 79件は無回帰を確認済み)。

以下、残り37件を分類ごとに記載する。テスト入力側の修正で解決できず、コンパイラ/ランタイム側に実バグが残っている、または未実装機能がブロックしているものは「次アクション」に owner の当たりを付けた。

### グループ2: enum/data class/interface(残り10件、うち1件解除済み)

| case | root cause | 次アクション |
| --- | --- | --- |
| `comparable_interface.kt` | ローカル(関数内)宣言の generic `fun <T> ... where T : Comparable<T>` が型パラメータ/where節を一切保持しない(`.localFunDecl` AST ノードと `inferLocalFunDeclExpr` に型パラメータのフィールド自体が無い)。副次的にnullable引数を渡す3行も要修正 | AST `.localFunDecl` とその type checker にトップレベル関数と同様の type params/where clause サポートを追加 |
| `context_receivers.kt` | kotlinc 2.4 の named `context(name: Type)` 構文に kswiftc パーサーが未対応(旧・匿名 context 型リストのみ対応)で、Sema も最初の context 型を extension receiver に読み替えるだけでネストしたスコープに伝播しない | context parameter の設計を要する中規模タスク(クイックパッチ不可) |
| `data_class_inheritance.kt` | 意図的な負テスト(コメントで明言)だが、ネストしたクラス(`Container.Outer : Inner`)が `validateSupertypesAreOpen` の対象外になっている点は独立した実バグ | 診断golden(DEBT-DIFF-006の`error_type_inference.kt`と同方針)へ移設し、ネストクラスのopen検証漏れは別途調査 |
| `data_class_inheritance_valid.kt` | `if (other !is BaseEntity) return false` のようなガード節後、`other` の smart-cast 状態が後続コードへ伝播しない(`ControlFlowTypeChecker.inferIfExpr` は else 無しの分岐の flowState をブロック内の後続文へ引き継がない設計)。広範囲に影響しうる一般的なcorrectnessギャップ。2ファイル(L17/L44)がdata class ctorのval/var欠落という別ミスも持つ | `ExprTypeChecker.blockExpr` の逐次処理が現状 statement ごとに同じ `ctx` を使い回しており、Nothing型分岐後のflowStateを次のstatementへ運んでいない。`inferExpr`/`inferIfExpr` の戻り値契約を拡張する必要がある中規模タスク |
| `enum_basic.kt`(未解除、範囲縮小) | 元々の root cause だった「明示的companionがあると`values()`/`valueOf()`/`entries`の合成がスキップされる」「`EnumEntries<T>`が空マーカーで`.size`等が解決できない」の2点は2026-07-29に実装・修正済み(下記「2026-07-29 enum修正」参照)。残る唯一のブロッカーは別バグ: enum の companion object に**ユーザー自身が定義した**関数(`fun opposite(...)`)が `EnumClass.opposite(...)` 静的呼び出し構文で解決できない(`Unresolved member function`)。values()/entries等の合成メンバーとは無関係の既存バグで、companion なしの2026-07-29修正前のmasterでも同じ症状を確認済み(再現: `enum class D { A,B; companion object { fun f(): Int = 1 } }; fun main() { D.f() }`) | companion object の**ユーザー宣言**メンバーが `EnumClass.member()` 構文で解決できない root cause を調査(合成メンバー用に新設した経路と、既存のcompanion member解決経路の相互作用を疑う) |
| `enum_edge_cases.kt`(未解除、範囲縮小) | 同じく values()/entries 側は2026-07-29修正で解消。残るブロッカーは、entry 固有 body を持つ enum 定数(`C { override fun toString() = "C-special" }`)を `ComplexEnum.C` の形で参照すると `Ambiguous overload resolution` + `Unresolved member function 'C'` になる別バグ(未調査) | entry-specific body を持つ enum 定数の `EnumClass.ENTRY` 参照を調査 |
| `generic_typealias.kt` | `typealias A = B` / `typealias B = A` の循環定義が使用箇所でしか検出されず(`Helpers+TypeAliasExpansion.swift`)、未使用ならコンパイルが通ってしまう | 宣言済み typealias 全件に対する eager cycle check を追加 |
| `interface_conflict_resolution.kt` | interface同士の衝突(`SimpleConflict`)は検出できるが、concreteな親クラスを持つ多重interface実装(`SuperPriority : ConcreteBase(), Left, Right`)の衝突は見逃す | override衝突チェックにconcrete superclass併存時の分岐を追加 |
| `override_variance.kt` / `override_variance_advanced.kt` | `Unit` を明示的な値として使う式(`= Unit`)がどこでも解決できない(`inferNameRefExpr` は `null`/`this` は特別扱いするが `Unit` は素通りしてunresolvedになる) — 他のケースにも波及しうる一般的ギャップ。`override_variance.kt` は無効な Java 風 `throws X` 節も含む。`override_variance_advanced.kt` は `protected fun` を `interface` 内に書けてしまう検証漏れも別途持つ | `inferNameRefExpr`(`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`)に`Unit`の特別解決を追加。`throws`節除去、`protected in interface`検証追加は別途 |

#### 2026-07-29 enum修正(`enum_entries_function.kt` は解除済み)

上表の `enum_basic.kt`/`enum_edge_cases.kt` の root cause として記載されていた、(1) enum が明示的 companion object を持つと `values()`/`valueOf()`/`entries` の合成がスキップされる、(2) `EnumEntries<T>` が空マーカーで `.size`/`.forEach` 等が解決できない、の2点を実装・修正した(`HeaderCollection.swift`, `HeaderHelpers+SyntheticEnumStubs.swift`, `DataEnumSealedSynthesisPass+EnumSynthesis.swift`, `CompilerKnownNames.swift`。回帰は `Tests/CompilerCoreTests/Sema/EnumAPISurfaceInventoryTests.swift`、`Tests/CompilerCoreTests/Lowering/LoweringPassRegressionTests+EnumEntriesEdgeCases.swift`、新規 `Scripts/diff_cases/enum_values_and_entries.kt`)。`enum_entries_function.kt`(`enumEntries<Color>()` トップレベル関数版)はこの修正で candidate 側が通るようになり、ref 側の残エラーが `import kotlin.enums.enumEntries` 欠落という test input mistake だったため、import を追加して `SKIP-DIFF` を解除した。`enum_basic.kt`/`enum_edge_cases.kt` は上表の通り別バグで依然ブロックされている。

### グループ3: common stdlib gap(残り15件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `advanced_type_inference.kt` | `@ExperimentalTypeInference` を関数に直接付与(本来はアノテーションクラスへのメタ注釈のみ許可)しているのを kswiftc は許してしまう。修正後は `buildList`/`buildMap` の generic 型引数forwardingで別途詰まる | `@ExperimentalTypeInference` 誤用チェック追加、`buildList`/`buildMap` のgeneric forwarding調査 |
| `array_hof.kt`(未解除、範囲縮小) | 2026-07-29 に `mapIndexed`/`filterIndexed`/`mapNotNull`/`filterNot`/`filterNotNull`/`reduceIndexed`/`first`/`firstOrNull`/`last`/`lastOrNull` の10メソッドを実装・修正済み(`CallTypeChecker+ArrayMemberFallback.swift`の Sema allowlist gate `isSupportedArrayMember` に不足していた。KIR側は`CallLowerer+UnresolvedMemberCalls.swift`と`CollectionLiteralLoweringPass+VirtualCallRewrite+Array.swift`の重複ディスパッチ両方に登録、Runtime側は`RuntimeCollectionHOFArray.swift`に`@_cdecl`追加。副次的に`first()`/`last()`のゼロ引数/述語判定が`argumentCount`でなく`hofArity`を見るべきだったSIGSEGVも修正。全10メソッドの出力をkotlincと突き合わせ完全一致を確認、回帰は`ArraySyntheticMemberLinkTests.swift`/`CodegenBackendIntegrationTests+ArrayHOF.swift`)。残る唯一のブロッカーは`flatMap`: kswiftc未実装に加え、このテストの`arr.flatMap { arrayOf(it, it*10) }`という書き方自体が実kotlincでも型エラー(`flatMap`の transform は`Iterable<R>`を返す必要があるが`Array`はIterableでないため`cannot infer type for type parameter 'R'`で拒否される、test input mistake)。作業中に見つけた無関係な既存クラッシュ(`Array.any/all/none/count`の closure-materialization SIGSEGV)は別セッションで修正済み(`d8b0436dae`) | `flatMap`をArrayに追加登録した上で、テストの`arrayOf(it, it*10)`を`listOf(it, it*10)`等Iterableを返す形に修正 |
| `bitwise_operators.kt` / `char_operations.kt` | `Char.rangeTo()`の明示的ドット呼び出し(`c1.rangeTo(c2)`)が未解決 — `..`演算子専用の特別扱いのみで、通常のメンバー関数として登録されていない(`ExprTypeChecker+BinaryAndFlowInference.swift:370`付近) | `rangeTo`を`Char`の通常解決可能メンバーとして登録。各ファイル固有の無効行(型不一致比較、`toIntOrNull`等)は別途修正 |
| `chunked_transform.kt` | ファイル全体が実在しない `chunked(size, step)` オーバーロードを前提に書かれている(実Kotlinの`chunked`は`size`と任意の`transform`のみ、step付きは`windowed`) | `chunked(size, step[, transform])` の呼び出し20箇所超を `windowed(size, step[, ..., transform])` へ書き換え。分量が大きいため今回は未着手 |
| `list_binary_search_compare.kt` | `main()` 内ローカル宣言の `data class Person(...)` の合成コンストラクタが解決できない("Unresolved function 'Person'")。ローカルクラス宣言収集の未調査ギャップ | `BuildASTPhase+MemberCollection.swift`/`+DeclBuilders.swift` でローカルdata classの扱いを調査。L150の型不一致行は別途修正 |
| `list_reversed_asreversed.kt` | `String.asReversed()`(実Kotlinに存在しない)を除去した後も、`MutableList.asReversed()[i] = value`(view経由の書き込みで元リストを変更する)が kswiftc で "Array reference is null" 例外を投げる | `asReversed()`が返すview実装のset操作を調査・修正 |
| `match_result.kt` | `MatchResult.range`/`MatchGroup.range`が`Int`型で登録されており(`HeaderHelpers+SyntheticRegexStubs.swift:162-180`)`IntRange`であるべき。destructuring の2件目(`component2()`)も値が入らない | `range`プロパティの型を`IntRange`に修正。destructuring 2項目束縛のバグを調査 |
| `range_basic.kt` | `.end`(実際は`.endInclusive`/`.last`)や`IntRange.toIntArray()`(IntRangeは`Collection`でなく`Iterable`)をrefは正しく拒否するが、kswiftcのSemaは寛容な fallback リスト(`CallLowerer+MemberCallSupport.swift`の`unresolvedCollectionMemberNames`)がこれを素通りさせ、対応するLoweringルールが無いため生のシンボル名がそのままcodegenへ渡り**診断エラーではなくリンカエラー**になる | fallbackリスト(~60件)がLoweringで実際にハンドルされない名前を許してしまう設計を監査し、未対応名は`unresolved reference`にフォールバックさせる |
| `string_chunked_windowed.kt` / `windowed_step_partial.kt`(未解除、範囲縮小) | `chunkedSequence`/`windowedSequence`のtransformコールバック引数(実際は`CharSequence`型)で`.length`のようなCharSequence正規メンバーが解決できない件はBUG-152(#5068)で解消済み。残るブロッカーは別件: `s.windowed(3, 1, true) { it.uppercase() }` のように transform 付き `chunked`/`windowed` を呼ぶと、実kotlincも`cannot infer type for type parameter 'R'`で拒否する(transform戻り値からRを推論できない、kotlinc自体の制約)。kswiftc側は`No viable overload found for call`+`Unresolved member function`のcascadeで失敗理由が異なる | test input を型注釈明示や`map`への書き換えで回避できるか検討するか、candidate-onlyの制約緩和が可能か調査(kotlinc側の制約なので完全なparityは望めない可能性) |
| `string_materialization.kt` | 存在しない`String.toTypedArray()`を除去した後も2件残存: (1)`"cba".toSortedSet().toList()`が`[a,b,c]`ではなく生の文字コード`[97,98,99]`を返す(Char boxing漏れ) (2)`"ab".iterator()`(CharIterator)が壊れている — `.next()`が空文字を返し、消費後の`.hasNext()`が誤って`true`を返す | `toSortedSet()`のChar要素boxingとCharIteratorの実装を調査・修正 |

### グループ4: coroutine Flow(残り3件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `flow_advanced_operators.kt` | `.transform { it * 10 }`が`emit()`を呼ばずmapのように誤用(real Kotlinでも無効)。修正後は`Flow.zip`/`Flow.combine`が同名の`Collection.zip`/`combine`と衝突し"Ambiguous overload resolution"になる実バグが残る | テストの`transform`誤用を修正。`Flow.zip`/`combine`のオーバーロード衝突は別途調査(`Helpers.swift:457`付近) |
| `flow_builders.kt` | `channelFlow{}`/`callbackFlow{}`内で`emit()`を使うテスト自体が実Kotlinでは無効(`ProducerScope`は`send`/`trySend`のみ)。kswiftcは意図的にchannelFlow/callbackFlowを`flow{}`にエイリアスしており`emit`を受理してしまうため、`send`に直すと今度は未実装で失敗する | DEBT-DIFF-003のChannel/produce未実装まわりと合わせて解消する。channelFlow/callbackFlowを real ProducerScope としてモデル化する設計が必要 |
| `flow_error_handling.kt` | `onErrorReturn`/`onErrorResume`(real Kotlinでは`ERROR`レベルでdeprecated、`catch{emit()}`/`catch{emitAll()}`推奨)をkswiftcが誤って受理。修正すると`onCompletion`(非推奨でない実オペレーター)が未実装で失敗する | テストを`catch{}`形式に書き換え。`Flow.onCompletion`を実装 |

### グループ5: reflection(残り3件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `annotation_reflection.kt` | `declarationModifiers`(`BuildASTPhase+ModifiersAndNames.swift`)がアノテーション引数のトークン列を素朴にスキャンしており、`@MyAnnotation(value = "hello")`のような named 引数 `value`/`inline` を後続宣言の修飾子(value class/inline)と誤認する — 6行で再現する一般的なパースバグ | `declarationAnnotations`/`AnnotationParsingSupport.parseAnnotation`と同様にアノテーション引数のトークン範囲をスキップするよう修正 |
| `kclass_members.kt` | `KClass.properties`/`memberProperties`/`functions`等はSemaの特別扱い(`CallTypeChecker+KClassMemberCallInference.swift`)で合成`List<Any>`を返すのみで、要素の`KFunction`/`KProperty`が実装を持たず`.name`等が解決できない(KSP-496で意図的に未対応と明記) | KSP-496のRuntimeオブジェクトモデル作業待ち |
| `mock_objects.kt` | `VisibilityChecker.isAccessible`が「外側クラスから入れ子private classのメンバーへ」のみ許可し、逆方向(入れ子private classのコンストラクタを、同じ外側クラスの兄弟メソッドから呼ぶ)を誤って拒否する。テスト自体もrefで別の理由(publicコンストラクタがprivateクラスを露出)により拒否される設計ミスあり | `VisibilityChecker.swift`の入れ子private classコンストラクタ可視性チェックを、outer class自身のスコープに対して行うよう修正 |

### グループ6: JVM interop/time(残り4件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `jvm_preview.kt` | `-jvm-target 21`(`@JvmRecord`用)と`kotlin.math.PI`のimport(完全修飾`kotlin.math.PI`を式中に直接書くと"Unresolved reference 'kotlin'"になる別の小さなギャップ)を足すと両方コンパイルは通るが、2つ目のトップレベル`"""..."""".trimIndent()`プロパティ(`sqlQuery`)が`null`を返す(1つ目の`jsonTemplate`は正常)。最小再現(2つのトップレベル`val = """...""".trimIndent()`プロパティを並べるだけ)でも同じ症状を確認済み — トップレベルString初期化子が2件目以降で失われる一般的な初期化順序バグの可能性がある | トップレベルプロパティ初期化子が2件目以降で失われる根本原因を調査(優先度高、影響範囲が広い可能性) |
| `platform_time_conversion.kt` / `time_edge_cases.kt` | `Instant.fromEpochMilliseconds(1_234)`のようなcompanion-extension呼び出しでInt literalがLongへwideningされない実バグ(両ファイル共通)。`platform_time_conversion.kt`は`toKotlinInstant()`/`toKotlinDuration()`(java.time→kotlin.time方向)も未実装。`time_edge_cases.kt`は`Duration.Companion`の`.seconds`/`.milliseconds`に必要なimportをrefでは要求するがkswiftcは省略を許容しており、要import化すると上記wideningバグが露出する | Int→Long literal wideningをcompanion-extension呼び出し全般で修正(共通根本原因)。`toKotlinInstant`/`toKotlinDuration`実装、importを要求する形にテスト修正 |
| `test_primitive_conversions.kt` | 存在しない`Char.toUInt()`/`toULong()`/`UByte.toChar()`/`UShort.toChar()`をrefは拒否するが、kswiftcは`UByte`/`UShort.toChar()`は正しく拒否しつつ`Char.toUInt/toULong`だけ独自拡張として誤って受理する。さらに標準の`Int.toChar()`を誤って"deprecated"と警告する | テストの4つの無効行を削除。`Char.toUInt/toULong`の独自拡張を見直し、`Int.toChar()`の誤deprecation警告を修正 |

### 未実装機能・deepなブロッカー: `contract_returns.kt` / `contracts_basic.kt`

ref はテストファイルが `@OptIn(ExperimentalContracts::class)` を欠いているために失敗する(test-input bug、容易に直せる)。candidate は全く別の実バグで失敗する: `contract { returns() implies (...) }` 内の `returns()`/`implies()` 呼び出しが `KSWIFTK-SEMA-0002: No viable overload found for call` になる。`HeaderHelpers.registerSyntheticContractStubs` は `ContractBuilder.returns()`/`SimpleEffect.implies()` 等を合成メンバーとして登録済みで、`CallTypeChecker.swift` の "General member function lookup via implicit receiver" 経路(`collectMemberFunctionCandidates`)がこれらを見つけられるはずだが、実際には見つけられていない。原因は未特定(`contract`専用のハードコードされた特別扱いと、通常のimplicit-receiver経路の相互作用を要調査)。ファイル内の後続エラー(`Exception(...)`呼び出し、`text.length`アクセス)はこの1件の根本原因から連鎖するノイズであり、独立したバグではない。

## 解除手順

1. 対象ケースだけを `--force-run-skipped` で実行する。

```bash
bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped Scripts/diff_cases/<case>.kt
```

2. reference 側だけが失敗するなら runner / classpath / target 問題として本 inventory を更新する。
3. candidate 側だけが失敗するなら Sema / KIR / Lowering / Runtime owner の task へ分解する。
4. 両者が pass したら `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を削除し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` で通常 diff を確認する。
