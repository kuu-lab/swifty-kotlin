# diff_kotlinc skip inventory

最終更新: 2026-07-09

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

## 現在値

| Debt | 件数 | 主因 | 優先アクション |
| --- | ---: | --- | --- |
| DEBT-DIFF-001 | 22 | JVM kotlinc reference 不成立、外部 jar / runtime-only | keep / runner / dependency injection を個別決定 |
| DEBT-DIFF-002 | 8 | script 起動 timeout（3件）／ script 実行能力の欠如（4件、2026-07-09 に timeout 無関係と確定）／ 非決定性出力（1件） | timeout-only suspect 3件は timeout 分離後に再判定。top-level 4件は kswiftc 側の script 実行能力（トップレベル `fun` と文の混在）実装待ち |
| DEBT-DIFF-003 | 14 | advanced coroutine / channel / Flow / structured concurrency | API 領域ごとに STDLIB-CORO / DEBT-CORO へ分割 |
| DEBT-DIFF-004 | 5 | value class boxing / generics / interface / collection | Sema / KIR / Lowering / Runtime ABI に分解 |
| DEBT-DIFF-005 | 15 | common stdlib / runtime surface gap、または synthetic surface | API 領域別に実装 owner と reference 可否を分離 |
| DEBT-DIFF-006 | 3 | type inference / variance / boxed numeric lowering | diagnostic case または parity regression へ分解 |
| DEBT-DIFF-007 | 1 | `firstOrNull { predicate }` の trailing-lambda 呼び出しが無引数オーバーロードに誤解決 | overload resolution（Sema）の呼び出し側解決ロジックを調査 |
| DEBT-DIFF-008 | 1 | `vararg items: Any` 経由で取り出した `Boolean` の `toString()` が boxing 境界で壊れる | Runtime ABI / boxing boundary（`ABILoweringPass` 周辺）を調査 |

## DEBT-DIFF-001: reference target / classpath / runtime-only

### keep skip: JVM kotlinc を oracle にしない

| 領域 | cases | 理由 | 次アクション |
| --- | --- | --- | --- |
| Kotlin/Native / cinterop | `native_annotations.kt`, `native_api.kt`, `platform_info.kt`, `system_get_time_nanos.kt` | `kotlin.native.*`, `kotlinx.cinterop.*`, Native-only API は JVM reference で解決不能 | Native surface の Sema / golden または target 専用 smoke へ移す |
| Kotlin/JS | `js_annotations.kt`, `js_api.kt` | `kotlin.js.*` / JS external declarations は JVM reference で解決不能 | JS/Wasm stub cleanup の target-out backlog と接続する |
| Runtime-only system API | `system_process_start_nanos.kt` | `System.processStartNanos()` は KSwiftK runtime 独自 API | Runtime unit test または candidate-only smoke に移す |
| custom JDBC runtime | `jdbc_basic.kt`, `prepared_statement_complete.kt`, `resultset_complete.kt`, `connection_validation.kt`, `transaction_management.kt` | `jdbc:kswiftk:memory` driver は kotlinc/JVM 側に無い | SQLite/JDBC reference driver を注入するか、Runtime JDBC suite へ移す |

### runner / dependency injection で戻せる候補

| 領域 | cases | 現状 | 次アクション |
| --- | --- | --- | --- |
| JVM assert mode | `assertions.kt` | KSwiftK は assert 有効、JVM は既定で無効 | `JAVA_FLAGS: -ea` 相当の directive を追加して通常 diff へ戻す |
| KMP expect/actual | `kmp_common.kt` | kotlinc に multiplatform flags を渡していない | case-specific `KOTLINC_FLAGS` で再現できるか検証し、不可なら KMP runner へ分離 |
| `kotlin.io.path` | `path_basic.kt` | JVM-specific path API / import surface の扱いが曖昧 | JVM interop 対象として維持するなら reference classpath/import を修正、target 外なら別 backlog へ移す |
| serialization | `custom_serializer.kt`, `dataclass_serialization.kt`, `json_serialization.kt`, `collection_serialization.kt` | `kotlinx-serialization` jar / plugin が無い | dependency injection だけで動く範囲と compiler plugin 必須範囲を分ける |
| SLF4J / logging | `logging_basic.kt`, `logging_advanced.kt` | `org.slf4j` jar / runtime-only logger が無い | `slf4j-api` + binding 注入で戻せる basic と runtime-only advanced を分ける |
| compiler plugin API | `compiler_plugin_api.kt` | case 自体は self-contained に見えるが skip 理由が generic | `--force-run-skipped` で再判定し、reference 阻害が無ければ DEBT-DIFF-006 か通常 diff へ移す |

## DEBT-DIFF-002: script-style cases

| グループ | cases | blocker | 次アクション |
| --- | --- | --- | --- |
| timeout-only suspect | `script_imports.kt`, `script_repl_interactive.kt`, `script_repl_patterns.kt` | script mode は `kotlinc -script` の compile + run を `RUN_TIMEOUT` で縛っている | script 専用 timeout を `COMPILE_TIMEOUT` 系へ分離し、再実行して pass なら skip を外す（本節の対象外。未着手） |
| top-level functions / custom declarations | `script_function_basic.kt`, `script_function_advanced.kt`, `script_toplevel_functions.kt`, `script_import_custom.kt` | 2026-07-09 実測済み。timeout ではなく kswiftc 側の script 実行能力そのものの欠如（詳細は下） | 解決済み分類。skip は維持するが理由コメントと検証手段を確定した |
| stdlib import + nondeterminism | `script_import_stdlib.kt` | `shuffled()` が出力非決定になり得る | deterministic input に直すか、script runner ではなく API 個別 diff に分解 |

既に skip されていない `script_*.kt` が複数あるため、script 全体ではなく上記 8 件だけを再判定する。

2026-07-09 追記: 本タスクの検証中、マシン全体が高負荷（他 worktree の並行ビルド/テストで `uptime` の load average が 700 超）だった際に、`script_toplevel_vars.kt` を含む未 skip の `script_*.kt` ケースが `--run-timeout 60`（既定の6倍）でも reference 側（`kotlinc -script` の JVM 起動 + compile）だけで timeout する事象を観測した。同条件で candidate（kswiftc）側は高速かつ正しい出力を返しており、kswiftc 側の regression ではない。timeout-only suspect 3件に限らず、script モード全体が高負荷環境での `RUN_TIMEOUT` に弱いことを示す傍証だが、通常負荷（CI 等の専有環境）での再現性は未確認であり、本タスクの対象外として着手していない。

### top-level functions / custom declarations: 2026-07-09 実測結果

`bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped Scripts/diff_cases/<case>.kt` を4ケースそれぞれに実行した結果、いずれも timeout（`COMPILE_TIMEOUT=120s` / `RUN_TIMEOUT=10s`）に達する前、10秒未満で次のリンクエラーにより即座に失敗することを確認した。timeout 分離は本グループには無関係であり、実施していない。

```
error KSWIFTK-LINK-0002: No entry point 'main' function found for executable emission.
```

原因は `Sources/CompilerCore/Parser/KotlinParser.swift` の `parseFile()`（`sawTopLevelStatement` / `sawNonPropertyDecl` の判定、L15-101）にある。kswiftc がトップレベル文から暗黙 `main` を合成する（`SyntaxKind.script` として扱う）のは、「トップレベル文が1つ以上あり、かつ `val`/`var` 以外のトップレベル宣言が1つも無い」場合のみ（L87-91）。`fun` 宣言が1つでもあると通常の `.kotlinFile` 扱いになり、`Sources/CompilerCore/Driver/FrontendPhases.swift` の `buildFileAST()`（L452-454）がトップレベル文を **診断なしに黙って破棄**する。結果、`main` がどこにも存在しないまま link phase まで進み、`KSWIFTK-LINK-0002` として顕在化する。kotlinc の実際の `.kts` script mode（Kotlin 公式文法の `script` 生成規則、`docs/spec.md:368-369,405` 参照）にはこの制限が無く、トップレベル関数宣言と文が自由に混在できる。`Tests/CompilerCoreTests/Integration/ScriptModeTests.swift` の既存テストは常に明示 `fun main()` と組み合わせており、まさにこの未対応パターン（トップレベル `fun` + トップレベル文、`main` 無し）を回避している。

4ケースのうち3ケースは、`println` 呼び出しだけを `fun main() { ... }` に移し、それ以外の宣言はトップレベルのまま残した通常 `.kt` 双子ケースを作成し、force 無しの通常 diff で green になることを確認した（=ロジック自体は kotlinc と完全に一致し、blocker は script 実行能力の欠如のみ）。残り1ケース（`script_function_advanced.kt`）は双子ケース作成中に stdlib 呼び出し自体の独立した実装バグが2件見つかったため、それぞれ最小再現ケースへ分離して DEBT-DIFF-007 / DEBT-DIFF-008 として新規に起票した。

| script ケース | 判定 | 対応 |
| --- | --- | --- |
| `script_function_basic.kt` | script 実行能力の欠如のみ。ロジック（関数呼び出し・文字列補間）は正しい | `top_level_function_basic.kt`（通常 diff、green）で証明。skip は維持、理由コメントのみ更新 |
| `script_toplevel_functions.kt` | script 実行能力の欠如のみ。再帰関数（`factorial`）を含めロジックは正しい | `top_level_function_recursion.kt`（通常 diff、green）で証明。skip は維持、理由コメントのみ更新 |
| `script_import_custom.kt` | script 実行能力の欠如のみ。拡張関数・`data class`・トップレベル `val` 初期化子・文字列テンプレート内メソッド呼び出しは正しい | `top_level_extension_data_class.kt`（通常 diff、green）で証明。skip は維持、理由コメントのみ更新 |
| `script_function_advanced.kt` | script 実行能力の欠如 **に加えて** stdlib 呼び出し自体に2つの独立したバグ | `firstornull_trailing_lambda.kt`（DEBT-DIFF-007）と `vararg_any_boolean_element.kt`（DEBT-DIFF-008）に最小分離。skip は維持 |

**注意**: script 実行能力そのもの（トップレベル `fun` と文の混在サポート）を実装しない限り、この4ケースを `SKIP-DIFF` から外すことはできない。将来実装する際、`script_function_advanced.kt` だけは DEBT-DIFF-007 / 008 も同時に解決していないと通らない。

## DEBT-DIFF-003: advanced coroutine / channel / Flow

`Scripts/diff_kotlinc.sh` は `kotlinx.coroutines` import を検出して `kotlinx-coroutines-core-jvm` を取得できるため、現在の skip 主因は reference classpath ではなく KSwiftK 側の API / runtime parity である。

| 領域 | cases | owner |
| --- | --- | --- |
| base suspend / withContext / exception | `coroutine_base_edge_cases.kt`, `coroutine_context_switching.kt`, `coroutine_exception_handling.kt`, `coroutine_edge_cases.kt` | `STDLIB-CORO-001` と `DEBT-CORO-003` |
| cancellation / lifecycle | `coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`, `coroutine_scope_lifecycle.kt` | cancellation semantics を `STDLIB-CORO-001` の残課題として切る |
| structured concurrency / Deferred / Supervisor | `coroutine_deferred.kt`, `coroutine_structured_concurrency.kt`, `coroutine_supervisor_job.kt` | Job hierarchy / async-await / supervisor semantics の runtime task |
| Channel / produce / Flow backpressure | `channel_basic.kt`, `coroutine_channels_advanced.kt`, `coroutine_flow_backpressure.kt` | `DEBT-CORO-002` の producer / channel runtime と Flow lowering |
| sync primitives | `coroutine_mutex_semaphore.kt` | Mutex / Semaphore API surface と scheduler interaction |

解除順は、`runBlocking` + simple suspend、`withContext`、`async/await`、Channel、Flow、Supervisor / cancellation の順にする。

## DEBT-DIFF-004: value class parity

| cases | 主な責務 | 次アクション |
| --- | --- | --- |
| `value_class_boxing_boundaries.kt` | Lowering / Runtime ABI | `Any`, nullable, cast, collection element 境界の box/unbox insertion を固定 |
| `value_class_generics.kt` | Sema / KIR | generic value class、bounds、`sortedBy` lambda receiver の型を確認 |
| `value_class_collections.kt` | Lowering / Runtime ABI | List / Map / Array storage、key equality/hash、HOF iteration 境界を確認 |
| `value_class_interfaces.kt` | Sema / KIR / dispatch | value class の interface 実装と boxed interface dispatch を確認 |
| `value_class_interop.kt` | Lowering / primitive ABI | Long / Double underlying value の ABI、string interpolation、list map を確認 |

分割タスク:

- Sema: value class declaration, generic value class, interface implementation, nullable value class の型表現を監査する。
- KIR / Lowering: `Any` / generic / interface / collection / nullable 境界で box/unbox を挿入する。
- Runtime ABI: value class box の equality / hash / type cast / array-list-map storage を検証する。
- Regression: 上記 5 ケースを `--force-run-skipped` で green にしてから skip を外す。

## DEBT-DIFF-005: common stdlib surface gap

| 領域 | cases | 判定 | 次アクション |
| --- | --- | --- | --- |
| `java.math.BigInteger` | `big_integer.kt` | Java interop surface gap | BigInteger を対象に残すなら Java interop task、対象外なら target-out backlog |
| Sequence common API | `flatten_sequence_edge_cases.kt` | `Sequence.flatten` 実装 gap | `Stdlib/kotlin/sequences` / runtime sequence bridge の実装後に通常 diff へ |
| KSwiftK synthetic Sequence surface | `sequence_takelast.kt`, `sequence_takelastwhile.kt`, `sequence_subtract.kt` | JVM kotlinc に無い surface | public surface として残す理由を再確認し、残すなら candidate-only test へ移す |
| Scope functions | `scope_functions_edge_cases.kt` | common stdlib gap | `let` / `also` / `with` / `apply` / `takeIf` / `takeUnless` を API 別に分解 |
| Property delegates | `property_delegate_edge_cases.kt` | `lazy`, `Delegates.observable/vetoable` gap | delegate lowering と stdlib delegate API のどちらが blocker か分離 |
| Regex runtime edge | `regex_runtime_edge_cases.kt` | named group / invalid pattern parity | RuntimeRegex と diagnostic behavior の regression に分割 |
| ByteArray helpers | `string_tobytearray.kt` | `joinToString` / `contentEquals` Sema gap | ByteArray extension stubs + runtime helpers の task に分割 |
| File/use | `file_use_edge_cases.kt` | `Closeable.use` と `java.io.File` surface | `use` common helperと JVM file interop を分離 |
| Duration/time | `duration_operations.kt`, `experimental_time_edge_cases.kt` | formatting / timing-sensitive output | `Duration.toString` parity と monotonic time test determinism を分離 |
| Instant API surface | `instant_basic.kt` | kswiftc の synthetic Instant stub が `nanoOfSecond`/`until()` という実 API に無い名前を使っている（正しくは `nanosecondsOfSecond` / `Instant` 同士の `minus` 演算子）。加えて JVM kotlinc 側にも `import kotlin.time.*` + `Instant` 参照で `Duration.Companion.seconds` が unresolved になる別の compiler quirk がある（明示 import で回避可能） | `HeaderHelpers+SyntheticInstantStubs.swift` の名前を実 API に合わせて修正し、テストの import を明示化してから通常 diff へ戻す |
| Math/comparator | `math_trig_functions.kt`, `comparator_composition_edge_cases.kt` | math function / comparator API gap | math runtime ABI、Comparator composition API に分ける |

`experimental_time_edge_cases.kt` は実行速度差で stdout が揺れるため、固定 clock / larger duration / unit test のどれかへ寄せてから diff に戻す。

## DEBT-DIFF-006: inference / variance / boxed numeric lowering

| cases | 判定 | 次アクション |
| --- | --- | --- |
| `error_type_inference.kt` | compile-error expectation case | diff harness は現状 stderr parity を厳密比較しないため、diagnostic golden か error-code regression へ移す |
| `variance_generics.kt` | Sema variance checking gap | variance type checker の実装後に通常 diff へ戻す。実装前は Sema golden / diagnostic case として固定 |
| `math_rounding_functions.kt` | math API ではなく boxed `Double` iteration lowering bug | List<Double> iteration unboxing の最小再現を別 case 化し、math 関数 case から分離 |

## DEBT-DIFF-007: firstOrNull trailing-lambda overload resolution

| cases | 判定 | 次アクション |
| --- | --- | --- |
| `firstornull_trailing_lambda.kt` | `listOf(1, 2, 3).firstOrNull { it > 2 }` が `3` ではなく `1`（先頭要素）を返す | `firstOrNull { predicate }` の trailing-lambda 呼び出しが、述語ありオーバーロードではなく無引数の `firstOrNull()` に誤解決されている疑い。呼び出し側の overload resolution（Sema）を調査し、述語オーバーロードへ正しくディスパッチさせる |

2026-07-09、DEBT-DIFF-002 の `script_function_advanced.kt` 検証中に発見。`filter { it > 2 }` / `find { it > 2 }` / `any { it > 2 }` / `count { it > 2 }` / ラムダの直接呼び出し（`val pred: (Int) -> Boolean = { it > 2 }; pred(3)`）はすべて正しい結果を返すため、ラムダ実行そのものや比較演算子は壊れていない。ユーザー定義の `List<T>.firstOrNull` 拡張関数を伴わない、stdlib 単体の呼び出しでも再現するため、拡張関数の shadowing とは無関係。Kotlin stdlib で `find` は `firstOrNull` に委譲する定義だが、`find` は正しく動作し `firstOrNull` だけが誤動作する非対称性から、`firstOrNull` という名前・シグネチャ固有の解決経路（無引数オーバーロードとの混同）を疑う。

## DEBT-DIFF-008: vararg Any 経由の Boolean boxing

| cases | 判定 | 次アクション |
| --- | --- | --- |
| `vararg_any_boolean_element.kt` | `vararg items: Any` に渡した `Boolean`（`true`）を `items.forEach { println(it) }` で取り出すと `"true"` ではなく `"1"` と表示される | `Any` 型 vararg 配列に boxing された `Boolean` が `toString()` 経由で正しい型タグを保持していない。Runtime ABI / boxing boundary（`ABILoweringPass` 周辺）を調査する |

2026-07-09、DEBT-DIFF-002 の `script_function_advanced.kt` 検証中に発見。同じ vararg 配列内の `"Hello"`（String）と `42`（Int）は正しく表示されるため、`Any` vararg 自体や String/Int の boxing は壊れていない。Boolean 固有の boxing/toString 経路の問題であり、Char/Bool/Double のようなプリミティブが `Any` 境界を越える際に toString が壊れる既知のパターン（`MutableList.add` 等での類似事例）と根が近い可能性がある。

## 解除手順

1. 対象ケースだけを `--force-run-skipped` で実行する。

```bash
bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped Scripts/diff_cases/<case>.kt
```

2. reference 側だけが失敗するなら runner / classpath / target 問題として本 inventory を更新する。
3. candidate 側だけが失敗するなら Sema / KIR / Lowering / Runtime owner の task へ分解する。
4. 両者が pass したら `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を削除し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` で通常 diff を確認する。
