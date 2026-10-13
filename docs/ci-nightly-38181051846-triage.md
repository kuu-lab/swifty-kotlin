# Nightly run 38181051846 の残失敗再検証 (KUU-1943)

確認日: 2026-10-13 JST。親: [KUU-1943](https://linear.app/kuu/issue/KUU-1943)。
再検証基準: `a1ad746b646afab1ccb242033740e0c6528979e0`（開始時に fetch した最新 master）。

この親は調査台帳と独立修正への分割を担当する。compiler/runtime 修正は各子で扱い、
`1子チケット = 1 task = 1 branch = 1 PR` を維持する。
connection_validation の診断 oracle 修正は [PR #8785](https://github.com/kuu-lab/swifty-kotlin/pull/8785) が担当する。

## CI の確定記録

[Nightly Full Verification run 38181051846](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38181051846)
は SHA `24b4b55711c0d388edc868b5893688fa9e138b8d`、Ubuntu 24.04 x86_64 / Swift 6.3 /
release kswiftc / Kotlin 2.3.10 で実行した。

全文ログと全8個の diff artifact の TSV・失敗ディレクトリを照合した。
本文に列挙された19ケースは33件の失敗観測（O0 15件、O2 18件）。
加えて、候補専用 `stdlib_kotlin_native_concurrent_n_n` が O0/O2 各1件失敗しており、
diff TSV 全体は35件 / 20ケースだった。追加1件は19ケースの集計とは別枠にする。
失敗 artifact の input は現在の原ケースとすべて同一である。

debug test bundle の build は成功したが candidate-only connection_validation が失敗したため、
CompilerCore/Smoke と Backend/Runtime/CLI/LSP の後続テストジョブは skipped。
この run の release build 成功や、一部 diff 成功を全 Swift tests 成功として数えない。

全ジョブの状態、原本 SHA-256、終了値、診断、reference/candidate stdout と差分は
[CI evidence](fixtures/nightly-38181051846/evidence/ci-failures.json) に保存した。
クラッシュ stderr は先頭1600文字を収録し、完全ログは元 CI artifact を参照する。

## 検証方法と環境差

原ケース19件を変更せず、release compiler と新しく生成した共用 stdlib artifact で
各ケースを O0/O2 の順に1件ずつ実行した。O2 の user module に対しても artifact は
CI と同じ既定最適化で生成した。Kotlin 2.3.10 / Temurin JDK 21 を明示指定した。

```bash
swift build -c release --disable-sandbox
DIFF_KSWIFTC_FLAGS=-O0 KSWIFTC="$compiler" \
  KOTLINC="$kotlinc_2_3_10" JAVA_BIN="$jdk21_java" \
  /opt/homebrew/bin/bash Scripts/diff_kotlinc.sh \
  --no-parallel --compile-timeout 600 --stdlib-library "$fresh_stdlib" \
  Scripts/diff_cases/<case>.kt
DIFF_KSWIFTC_FLAGS=-O2 KSWIFTC="$compiler" \
  KOTLINC="$kotlinc_2_3_10" JAVA_BIN="$jdk21_java" \
  /opt/homebrew/bin/bash Scripts/diff_kotlinc.sh \
  --no-parallel --compile-timeout 600 --stdlib-library "$fresh_stdlib" \
  Scripts/diff_cases/<case>.kt
```

ローカルは macOS 27 arm64 / Apple Swift 6.4 / Homebrew LLVM 23.1.2。
LLVM の dylib を明示して artifact / warm / 全ケースに同じライブラリを使用した。
CI の Linux x86_64 / Swift 6.3 とは異なり、CI の backend LLVM 版は取得ログから特定できていない。
ローカルで再現しないケースを、CI 環境でも修正済みとは断定しない。
初回 sandbox_apply の環境エラーは製品 FAIL に数えない。
source injection、全 Swift tests、全 diff、Linux/Swift 6.3 での再実行は今回のローカル検証対象外。

## 最終結果と追跡先

調査・分割の範囲は完了。親の完了は全不具合の解消を意味しない。
指定19ケースは **O0 10 FAIL / 9 PASS、O2 12 FAIL / 7 PASS、合計22 FAIL / 16 PASS**。
環境 blocker は0。追加候補専用ケースは O0/O2 とも FAIL。
release build、新規 stdlib 生成、正規 runtime manifest の warm、hello stdout `hello` は成功した。

| 原ケース | CI O0 | CI O2 | local O0 | local O2 | 追跡先 |
|---|---|---|---|---|---|
| `annotation_reflection` | FAIL | FAIL | FAIL | FAIL | [KUU-1973](https://linear.app/kuu/issue/KUU-1973/kotlinreflectfullfindannotation-の-explicit-import-が未解決になる) |
| `metadata_api` | FAIL | FAIL | FAIL | FAIL | [KUU-1973](https://linear.app/kuu/issue/KUU-1973/kotlinreflectfullfindannotation-の-explicit-import-が未解決になる) |
| `kconstructor_basic` | FAIL | FAIL | FAIL | FAIL | [KUU-1974](https://linear.app/kuu/issue/KUU-1974/kotlinreflectfullprimaryconstructor-の公開-import-が未解決になる) |
| `stdlib_kotlin_reflect_KClass_n` | FAIL | FAIL | FAIL | FAIL | [KUU-1975](https://linear.app/kuu/issue/KUU-1975/kotlinreflectfullcast-safecast-の-explicit-import-が未解決になる) |
| `companion_property_direct_import` | FAIL | FAIL | FAIL | FAIL | [KUU-1976](https://linear.app/kuu/issue/KUU-1976/companion-property-の直接-import-alias-が-sema-0022-で再び未解決になる) |
| `coroutine_deferred` | FAIL | FAIL | FAIL | FAIL | [KUU-1977](https://linear.app/kuu/issue/KUU-1977/runblocking-内の-listmap-itawait-を-sema-0308-で誤拒否する) |
| `coroutine_context_element_get` | PASS | FAIL | PASS | FAIL | [KUU-1978](https://linear.app/kuu/issue/KUU-1978/o2-の-coroutinecontextfold-が-kk-context-fold-の引数数不一致を-emit-する) |
| `kotlinx_coroutines_cancellable_cont_parent` | FAIL | FAIL | FAIL | FAIL | [KUU-1979](https://linear.app/kuu/issue/KUU-1979/所有監査-pr-8307-で-cancellablecontinuation-parentprompt-callback) |
| `stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n` | FAIL | FAIL | FAIL | FAIL | [KUU-1980](https://linear.app/kuu/issue/KUU-1980/continuationinterceptorkey-を-any-経由で-coroutinecontextkey-と判定できない) |
| `measure_time_duration` | FAIL | FAIL | PASS | FAIL | O2: [KUU-1981](https://linear.app/kuu/issue/KUU-1981/o2-measuretime-が-basic-block-中間の-terminator-を含む-invalid-llvm-ir-になる) / O0: [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `stdlib_kotlin_collections_Map_first` | FAIL | FAIL | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `string_unsigned_throwing_parse` | FAIL | FAIL | FAIL | FAIL | [KUU-1982](https://linear.app/kuu/issue/KUU-1982/stringtoulong-の結果を-any-経由で表示すると上位ビット値が-null-1-になる) |
| `kclass_reflect_full_create_instance` | FAIL | FAIL | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `stdlib_kotlin_sequences_Sequence_sum` | FAIL | FAIL | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `duration_storage_coroutines` | PASS | FAIL | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `stack_overflow_error_catchable` | PASS | FAIL | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `kclass_supertypes_nested_flags` | FAIL | FAIL | FAIL | FAIL | [KUU-1983](https://linear.app/kuu/issue/KUU-1983/intclasssupertypes-が直接-supertype-でない-javaioserializable-を余分に表示する) |
| `coroutine_timeout_or_null_unit` | FAIL | PASS | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |
| `kotlinx_coroutines_channel_receive_try` | PASS | FAIL | PASS | PASS | [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) |

追加の `stdlib_kotlin_native_concurrent_n_n` は [KUU-1984](https://linear.app/kuu/issue/KUU-1984/withworker-receiver-内の-workerexecute-が-sema-0023-で未解決になる) が担当する。
O0/O2 とも `execute` 未解決と TYPE-0001 / SEMA-INFER。
存在しない `KOTLINC` / `JAVA_BIN` でも同じ診断を再確認し、候補専用を維持した。

## 反復結果

4ケース × O0/O2 × candidate/reference ×20回 = 320 run。全320 exit0、timeout0、
各 case/mode/side の stdout は単一だった。
`cancellable_cont_parent` candidate は40回すべて JVM と不一致。
`duration_storage_coroutines`、`coroutine_timeout_or_null_unit`、`channel_receive_try` の
candidate 120回はすべて JVM と一致した。今回の反復条件での観測であり、CI 条件の再現否定には使わない。

## 独立した13子

全13件は Kuu / バグバックログ (BUG) / Bug / Backlog、親 KUU-1943。
本文・snapshot SHA・原ケース・親子関係を読み戻し確認した。
修正候補11件、既存 PR の所有確認1件、Linux focused 再検証1件に分けた。

| 子 | 種別 | 範囲 |
|---|---|---|
| [KUU-1973](https://linear.app/kuu/issue/KUU-1973/kotlinreflectfullfindannotation-の-explicit-import-が未解決になる) | 修正候補 | kotlin.reflect.full.findAnnotation の explicit import が未解決になる |
| [KUU-1974](https://linear.app/kuu/issue/KUU-1974/kotlinreflectfullprimaryconstructor-の公開-import-が未解決になる) | 修正候補 | kotlin.reflect.full.primaryConstructor の公開 import が未解決になる |
| [KUU-1975](https://linear.app/kuu/issue/KUU-1975/kotlinreflectfullcast-safecast-の-explicit-import-が未解決になる) | 修正候補 | kotlin.reflect.full.cast / safeCast の explicit import が未解決になる |
| [KUU-1976](https://linear.app/kuu/issue/KUU-1976/companion-property-の直接-import-alias-が-sema-0022-で再び未解決になる) | 修正候補 | Companion property の直接 import / alias が SEMA-0022 で再び未解決になる |
| [KUU-1977](https://linear.app/kuu/issue/KUU-1977/runblocking-内の-listmap-itawait-を-sema-0308-で誤拒否する) | 修正候補 | runBlocking 内の List.map { it.await() } を SEMA-0308 で誤拒否する |
| [KUU-1978](https://linear.app/kuu/issue/KUU-1978/o2-の-coroutinecontextfold-が-kk-context-fold-の引数数不一致を-emit-する) | 修正候補 | O2 の CoroutineContext.fold が kk_context_fold の引数数不一致を emit する |
| [KUU-1979](https://linear.app/kuu/issue/KUU-1979/所有監査-pr-8307-で-cancellablecontinuation-parentprompt-callback) | 所有確認 | [所有監査] PR #8307 で CancellableContinuation parent/prompt callback の原ケースを検証する |
| [KUU-1980](https://linear.app/kuu/issue/KUU-1980/continuationinterceptorkey-を-any-経由で-coroutinecontextkey-と判定できない) | 修正候補 | ContinuationInterceptor.Key を Any 経由で CoroutineContext.Key と判定できない |
| [KUU-1981](https://linear.app/kuu/issue/KUU-1981/o2-measuretime-が-basic-block-中間の-terminator-を含む-invalid-llvm-ir-になる) | 修正候補 | O2 measureTime が basic block 中間の terminator を含む invalid LLVM IR になる |
| [KUU-1982](https://linear.app/kuu/issue/KUU-1982/stringtoulong-の結果を-any-経由で表示すると上位ビット値が-null-1-になる) | 修正候補 | String.toULong の結果を () -> Any 経由で表示すると上位ビット値が null / -1 になる |
| [KUU-1983](https://linear.app/kuu/issue/KUU-1983/intclasssupertypes-が直接-supertype-でない-javaioserializable-を余分に表示する) | 修正候補 | Int::class.supertypes が直接 supertype でない java.io.Serializable を余分に表示する |
| [KUU-1984](https://linear.app/kuu/issue/KUU-1984/withworker-receiver-内の-workerexecute-が-sema-0023-で未解決になる) | 修正候補 | withWorker receiver 内の Worker.execute が SEMA-0023 で未解決になる |
| [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) | Linux再検証 | [CI再検証] macOSで非再現の7ケースと measureTime O0 を Linux Swift6.3 で確認する |

`1子チケット = 1 task = 1 branch = 1 PR` を維持する。
今回の親は調査証拠のみを保存し、compiler/runtime、原ケース、expected、SKIP タグは変更していない。

## 非再現と既存所有の扱い

両mode PASS の7ケースと measureTime O0 は [KUU-1985](https://linear.app/kuu/issue/KUU-1985/ci再検証-macosで非再現の7ケースと-measuretime-o0-を-linux-swift63-で確認する) に引き継ぐ。
最新 master の Linux x86_64 / Swift6.3 / release / backend LLVM 条件で1ケースずつ確認し、
fresh/reused artifact の区別と toolchain の SHA・版を記録する。今回の macOS PASS を修正済みとは断定しない。

- parent/prompt callback は [KUU-1979](https://linear.app/kuu/issue/KUU-1979/所有監査-pr-8307-で-cancellablecontinuation-parentprompt-callback) で既存 KUU-1758 / [#8307](https://github.com/kuu-lab/swifty-kotlin/pull/8307) の固定 head `e2e6658fff6fee54977fb91600d6dad1e44e6705` を先に確認する。`initParent` が launch/async の completionJob を取得する直接修正を含む。残差だけ別修正にする。旧 KUU-1193 / #7674 の最初の join hang と異なり、今回は先頭31とcancelled行を出力してexit0だった。
- Sequence の捕捉 selector 例外には KUU-1750 / [#8292](https://github.com/kuu-lab/swifty-kotlin/pull/8292) head `7aa5110eeebfd94c108c365e3c3f90f74432a617` の wrapper/throw-channel 修正が所有候補。今回の原ケースは PASS なので重複 fix を作らず、Linux で再現する場合に既存所有を確認する。
- 負 Long/Duration は CI KIR で同じ `kk_with_timeout_or_null_throwing` に到達する。`runTimeoutBlock` の非正値 guard 欠落と [upstream1.10.2](https://raw.githubusercontent.com/Kotlin/kotlinx.coroutines/1.10.2/kotlinx-coroutines-core/common/src/Timeout.kt) の即時null契約を診断controlに残す。今回の一致を block 副作用の非実行まで証明したものとはしない。共通契約に対して1修正、独立変換欠陥を実証した場合のみ残差分割。
- O2 再帰と Channel 順序は今回 PASS。Linux で差分が残る場合、loop変換による実stack削減、producer/consumer dispatch の許容順序を監査してから修正を確定する。単なるstdout差分から例外伝播欠落やscheduler bugと断定しない。
- `measure_time_duration` の O0 は今回 PASS、O2 は BACKEND-1006 / basic block中間のterminatorを再現。[KUU-1981](https://linear.app/kuu/issue/KUU-1981/o2-measuretime-が-basic-block-中間の-terminator-を含む-invalid-llvm-ir-になる) が O2 を担当し、Linux 子から重複起票しない。診断は before optimization であり、LLVM optimizer 自身が壊したとは断定しない。
- ULong は typed equality が一致し、`() -> Any` の表示が乖離する。parse 不成功と断定せず boxing/unsigned identity を確認する。

reflection公開package/receiver/戻り型は Kotlin2.3.10 の
[KClasses.kt](https://raw.githubusercontent.com/JetBrains/kotlin/v2.3.10/core/reflection.jvm/src/kotlin/reflect/full/KClasses.kt) と
[KAnnotatedElements.kt](https://raw.githubusercontent.com/JetBrains/kotlin/v2.3.10/core/reflection.jvm/src/kotlin/reflect/full/KAnnotatedElements.kt)、
Native `Worker.execute` の member 契約は
[Worker.kt](https://raw.githubusercontent.com/JetBrains/kotlin/v2.3.10/kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Worker.kt) を参照する。
producer は capture可能/caller実行、非capture要求は job のみ。

## 保存証拠と未実行範囲

- [CI 全ジョブ・35失敗観測](fixtures/nightly-38181051846/evidence/ci-failures.json)
- [38条件・追加2条件・16組の反復集計・toolchain/全artifact file hash](fixtures/nightly-38181051846/evidence/local-observations.json)
- [case verdict TSV](fixtures/nightly-38181051846/evidence/results.tsv)、[追加候補専用 TSV](fixtures/nightly-38181051846/evidence/additional-candidate-only.tsv)、[320反復 TSV](fixtures/nightly-38181051846/evidence/repeats.tsv)
- [最終13境界と既存 issue/PR の監査](fixtures/nightly-38181051846/evidence/scope-audit.json)（検証前19境界は historical として識別）

compiler SHA-256: `7ec5e7e92e4e0b344918c9d1f86bc92c17eabfa77654aa0772c02dafc52ed91c`。
stdlib manifest hash: `38a615de8d71c6b4`。compiler・stdlib全file・原19入力のhashは実行前後一致。
全 stdout/stderr/binary/jar はローカル `/tmp/kuu1943-validation` に保持した。
compile失敗時の run は未実行として正規化し、元harness summaryの初期run exit0を実行成功として解釈しない。

source injection、全 Swift tests、全 diff、Linux/Swift6.3 の再実行、既存 PR head の追試は未実行。
独立レビューは集計・公開 API・既存 PR 差分・最終分割を確認し、追加build/testは実行していない。
以上は検証 snapshot `a1ad746b` の観測記録であり、PR公開時のbaseへの再検証結果ではない。
