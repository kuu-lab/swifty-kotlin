# Dead Code Audit（2026-06-12）

> **ステータス**: Section A（完全到達不能 102 個）と Section C（参照ゼロ Swift 関数 6 個）は **削除済み**。
> 参照元ファイル（`RuntimeLogging.swift`, `RuntimeFlowErrorHandling.swift` 等）も既に存在しない。
> Section B（テストのみ参照 120 個）はトリアージ完了（2026-06-23 実施）。RF-DEAD-002 結果参照。
> Section D（テストのみ参照 Swift シンボル）はトリアージ完了（2026-07-02 実施）。DEADCODE-013 結果参照。
> 本ドキュメントは監査の履歴記録として保持する。

TODO.md の Phase RF9（RF-DEAD-001〜004）の根拠インベントリ。検出手法と全リストを記録する。

## 検出手法

識別子トークン頻度解析（`Sources` / `Tests` / `Scripts` / `Package.swift` / `*.kt` 横断）で「宣言されているが参照ゼロ」のシンボルを抽出し、以下の到達経路を順に除外して確定した。

1. **静的 emit**: CompilerCore 内の `kk_*` 文字列リテラル参照
2. **動的 emit（文字列補間）**: `"kk_xxx_\(...)"` 形式 25 プレフィックス（`kk_op_` / `kk_range_` / `kk_base64_*_` / `kk_match_result_destructured_component` 等）。前方一致で除外
3. **動的 emit（表駆動）**: `StdlibSurfaceSpec.collectionHOFRuntimeLinkName` 経由の 164 link name（list / set / map / sequence の HOF。`array` は対象外）
4. **テスト参照**: `Tests/` からの直接呼び出し（語境界一致。superstring 誤検知に注意: `kk_http_client_post` は `kk_http_client_post_async` とは別物）
5. **Runtime 内部呼び出し**: 他のランタイム関数からの Swift レベル呼び出し
6. **プロトコル経由・エントリポイント**: `URLSessionTaskDelegate.urlSession(...)`（Foundation が呼ぶ）、`GoldenHarnessWorkerMain`（実行ターゲットエントリ）等は dead ではない

**重要**: `RuntimeABISpec`（`+ABIParity` / `+RuntimeOnlyBridge`）への登録は exported シンボルの必須ミラーであり、**使用の証拠ではない**。spec 登録のみで他に参照がない関数はコンパイル済み Kotlin プログラムから到達不能。

### 再現コマンド

```bash
# 1. Runtime の @_cdecl kk_* 一覧
grep -rhoE '@_cdecl\("kk_[a-zA-Z0-9_]+"\)' Sources/Runtime --include="*.swift" \
  | sed 's/@_cdecl("//;s/")//' | sort -u > /tmp/runtime_cdecl.txt

# 2. CompilerCore が静的に参照する kk_* 名
find Sources/CompilerCore -name "*.swift" -print0 | xargs -0 cat \
  | grep -oE 'kk_[a-zA-Z0-9_]+' | sort -u > /tmp/kk_compilercore.txt

# 3. 動的補間プレフィックス（前方一致除外用）
grep -rhoE '"kk_[a-zA-Z0-9_]*\\\(' Sources/CompilerCore --include="*.swift" \
  | sed 's/^"//;s/\\($//' | sort -u > /tmp/kk_dyn_prefixes.txt

# 4. 候補 = cdecl − CompilerCore 静的参照 − 動的プレフィックス前方一致
#    さらに Tests / Runtime 内部 / StdlibSurfaceSpec 表の参照カウントで分類
comm -23 /tmp/runtime_cdecl.txt /tmp/kk_compilercore.txt
```

## A. 完全到達不能の `kk_*` ランタイム関数（102 個）→ RF-DEAD-001 ✅ 削除済み

> **削除済み**: 以下のシンボルとその実装ファイル（`RuntimeLogging.swift`, `RuntimeFlowErrorHandling.swift` 等）はすべて削除された。下記リストは監査記録として残す。

~~Runtime 実装（`@_cdecl` 宣言）と `RuntimeABISpec` ミラーのみ存在。CompilerCore（静的・動的とも）、Tests、Runtime 内部、`Stdlib/*.kt` のいずれからも参照ゼロ。削除時は **Runtime 実装 + spec エントリをセットで削除**し、孤立する private ヘルパー・Box 型も同時に消す。~~

### ロギング（SLF4J 互換・JVM 専用でターゲット外）— 28 個

```
kk_adv_logger_get
kk_file_appender_new kk_rolling_appender_new kk_structured_appender_new
kk_mdc_clear kk_mdc_get kk_mdc_put kk_mdc_remove
kk_slf4j_is_debug_enabled kk_slf4j_is_error_enabled kk_slf4j_is_info_enabled
kk_slf4j_is_trace_enabled kk_slf4j_is_warn_enabled
kk_slf4j_log_debug kk_slf4j_log_debug_1
kk_slf4j_log_error kk_slf4j_log_error_1 kk_slf4j_log_error_2
kk_slf4j_log_info kk_slf4j_log_info_1 kk_slf4j_log_info_2
kk_slf4j_log_trace kk_slf4j_log_trace_1
kk_slf4j_log_warn kk_slf4j_log_warn_1 kk_slf4j_log_warn_2
kk_slf4j_logger_get kk_slf4j_set_level
```

主な実装場所: `Sources/Runtime/RuntimeLogging.swift`

### リフレクション — 28 個

```
kk_kclass_get_field_count kk_kclass_get_instance_size_words kk_kclass_get_qualified_name
kk_kclass_get_simple_name kk_kclass_get_superclass_name
kk_kclass_is_data_class kk_kclass_is_sealed_class kk_kclass_is_value_class
kk_kconstructor_call_0 kk_kconstructor_call_1 kk_kconstructor_call_2 kk_kconstructor_call_3
kk_kconstructor_call_vararg kk_kconstructor_get_arity kk_kconstructor_get_name
kk_kconstructor_get_parameters kk_kconstructor_get_return_type
kk_kconstructor_get_value_parameters kk_kconstructor_get_visibility kk_kconstructor_is_primary
kk_kproperty_get kk_kproperty_set
kk_kproperty_stub_get_value kk_kproperty_stub_getter kk_kproperty_stub_set_getter
kk_kproperty_stub_set_setter kk_kproperty_stub_set_value kk_kproperty_stub_setter
```

主な実装場所: `Sources/Runtime/RuntimeReflection.swift`

### coroutines / Flow — 19 個

```
kk_async_task_cancel kk_await_all
kk_broadcast_channel_create kk_broadcast_channel_unsubscribe
kk_callback_flow_await_close kk_callback_flow_create
kk_channel_flow_create kk_channel_flow_send kk_channel_flow_try_send
kk_context_get_exception_handler kk_coroutine_scope_get_parent
kk_flow_catch kk_flow_on_completion kk_flow_on_error_resume kk_flow_on_error_return
kk_flow_retry kk_flow_retry_when
kk_kxmini_async_with_dispatcher kk_kxmini_run_loop
```

主な実装場所: `Sources/Runtime/RuntimeFlowErrorHandling.swift`、`RuntimeCoroutineChannel.swift` 等

### 配列 HOF（共通 HOF 機構移行後の取り残し）— 8 個

```
kk_array_filterIndexed kk_array_filterNot kk_array_filterNotNull
kk_array_first kk_array_firstOrNull kk_array_last kk_array_lastOrNull
kk_array_mapIndexed
```

主な実装場所: `Sources/Runtime/RuntimeCollectionHOFArray.swift`（spec ミラーは `RuntimeABISpec+RuntimeOnlyBridge.swift` の `arrayHOFBridgeNames`）

### java.time / JS Date ブリッジ（JVM/JS 専用でターゲット外）— 3 個

```
kk_java_instant_of_epoch_milli kk_java_instant_of_epoch_second
```

### HTTP クライアント — 2 個

```
kk_http_client_get_async kk_http_client_post
```

（注: `kk_http_client_get` / `kk_http_client_post_async` / `kk_http_client_new` は TEST_ONLY 側）

### その他 — 8 個

```
kk_char_get kk_char_plus          # Char 演算は別経路（kk_op_* / インライン）で処理
kk_clock_gettime_realtime
kk_math_e kk_math_pi              # PI / E は定数としてインライン展開される
kk_mem_scope_enter
kk_native_alloc_bytes kk_native_heap_free
```

## B. テストのみが参照する `kk_*` 関数（120 個）→ RF-DEAD-002

CompilerCore が emit できないため Kotlin プログラムからは到達不能だが、`Tests/RuntimeTests` が Swift から直接呼んで延命している。「(a) 配線予定 / (b) テスト支援 API / (c) 削除」のトリアージが必要。

```
kk_array_mapNotNull
kk_assertions_enabled kk_assertions_reset kk_assertions_set_enabled
kk_atomic_bool_getAndUpdate kk_atomic_bool_updateAndGet
kk_atomic_int_array_addAndFetchAt kk_atomic_int_array_compareAndExchangeAt
kk_atomic_int_array_compareAndSetAt kk_atomic_int_array_decrementAndFetchAt
kk_atomic_int_array_exchangeAt kk_atomic_int_array_fetchAndAddAt
kk_atomic_int_array_fetchAndDecrementAt kk_atomic_int_array_fetchAndIncrementAt
kk_atomic_int_array_fetchAndUpdateAt kk_atomic_int_array_incrementAndFetchAt
kk_atomic_int_array_loadAt kk_atomic_int_array_size
kk_atomic_int_getAndUpdate kk_atomic_int_updateAndGet
kk_atomic_long_array_addAndFetchAt kk_atomic_long_array_compareAndExchangeAt
kk_atomic_long_array_compareAndSetAt kk_atomic_long_array_decrementAndFetchAt
kk_atomic_long_array_exchangeAt kk_atomic_long_array_fetchAndAddAt
kk_atomic_long_array_fetchAndDecrementAt kk_atomic_long_array_fetchAndIncrementAt
kk_atomic_long_array_fetchAndUpdateAt kk_atomic_long_array_incrementAndFetchAt
kk_atomic_long_array_loadAt kk_atomic_long_array_size
kk_atomic_long_getAndUpdate kk_atomic_long_updateAndGet
kk_atomic_ref_getAndUpdate kk_atomic_ref_updateAndGet
kk_base64_encodeToByteArray_instance kk_base64_encode_instance
kk_base64_withPadding_default kk_base64_withPadding_mime kk_base64_withPadding_urlsafe
kk_byte_to_char kk_byte_to_uint kk_byte_to_ulong
kk_channel_is_closed_token
kk_char_fromCode kk_char_minus
kk_check_not_null_lazy
kk_cleaner_clean
kk_clock_gettime_monotonic_ns kk_clock_monotonic_mark_now
kk_cname_lookup kk_cname_register
kk_context_get_name kk_context_release
kk_copaque_pointer_address kk_copaque_pointer_new
kk_coroutine_cancel kk_coroutine_name_get
kk_coroutine_scope_is_active kk_coroutine_scope_is_cancelled
kk_cpointer_address kk_cpointer_new
kk_delegate_get_value kk_delegate_set_value
kk_double_max_value kk_double_min_value kk_double_nan
kk_double_negative_infinity kk_double_positive_infinity
kk_exception_handler_invoke
kk_float_max_value kk_float_min_value kk_float_nan
kk_float_negative_infinity kk_float_positive_infinity
kk_flow_count kk_flow_emit_with_timestamp kk_flow_fold kk_flow_reduce
kk_freezable_atomic_ref_is_frozen kk_freezable_atomic_ref_store
kk_hexformat_prefix kk_hexformat_suffix
kk_http_client_get kk_http_client_new kk_http_client_post_async
kk_instant_from_epoch_seconds
kk_int_max_value kk_int_min_value
kk_kclass_get_arity
kk_kproperty_stub_create_full kk_kproperty_stub_is_const
kk_kproperty_stub_is_lateinit kk_kproperty_stub_visibility
kk_long_max_value kk_long_min_value
kk_output_stream_bufferedWriter_default
kk_panic
kk_pinned_get
kk_platform_isDebugBinary
kk_register_global_root kk_unregister_global_root
kk_require_not_null_lazy
kk_runtime_force_reset kk_runtime_heap_object_count
kk_set_count_predicate kk_set_filterNot kk_set_flatMap kk_set_forEach
kk_set_map kk_set_mapNotNull
kk_short_to_char kk_short_to_uint kk_short_to_ulong
kk_string_joinToString
kk_ulong_downTo
kk_url_decode kk_url_encode
kk_write_barrier
```

トリアージ時の注意:

- `kk_assertions_reset` / `kk_runtime_force_reset` / `kk_runtime_heap_object_count` はテスト間状態リセット・検査用のテスト支援 API の可能性が高い（(b) 該当）
- `kk_write_barrier` / `kk_register_global_root` / `kk_unregister_global_root` / `kk_panic` は GC・ランタイム基盤の名前だが現行 codegen は emit していない（global root は `kk_global_root_slot_*` 動的名で処理）。設計上の予約か取り残しかの判断が必要
- `kk_set_*` HOF 群は TEST-COL-012（TODO.md テスト改善タスク）が Codegen 統合テスト追加を予定している領域と重なる。削除ではなく配線が正解の可能性あり

> **注**: `kk_hexformat_prefix` / `kk_hexformat_suffix` / `kk_panic` / `kk_write_barrier` は監査時点でソースに存在せず（既削除またはリスト誤記）。実際に存在するのは 116 個。

### RF-DEAD-002 トリアージ結果（2026-06-23 実施）

#### (b) テスト支援 API — 5 個（コメント追記済み）

| 関数 | ファイル | 用途 |
|---|---|---|
| `kk_assertions_enabled` | `RuntimeDebug.swift` | テスト間 assert 状態検査 |
| `kk_assertions_reset` | `RuntimeDebug.swift` | テスト間 assert 状態リセット |
| `kk_assertions_set_enabled` | `RuntimeDebug.swift` | テスト間 assert 有効/無効切替 |
| `kk_runtime_force_reset` | `RuntimeGC.swift` | テスト間ランタイム全状態リセット |
| `kk_runtime_heap_object_count` | `RuntimeGC.swift` | テスト間ヒープオブジェクト数検査 |

#### (c) 削除 — 9 個

| 関数 | 削除済みファイル |
|---|---|
| `kk_http_client_new` | `RuntimeNetwork.swift` + `RuntimeABISpec+Network.swift` |
| `kk_http_client_get` | `RuntimeNetwork.swift` + `RuntimeABISpec+Network.swift` |
| `kk_http_client_post_async` | `RuntimeNetwork.swift` + `RuntimeABISpec+Network.swift` |
| `kk_parallel_pool_new` / `kk_parallel_stream_{from_collection,to_list,map,forEach,reduce}` | `RuntimeParallel.swift` + `RuntimeABISpec+Parallel.swift` |

テスト: `Tests/RuntimeTests/RuntimeHTTPClientTests.swift` / `Tests/RuntimeTests/RuntimeParallelTests.swift` 全削除。

#### (a) 配線予定 — 108 個

| タスク / 領域 | 関数群 | ファイル |
|---|---|---|
| **MIGRATION-ATOMIC-001** (AtomicIntArray) | `kk_atomic_int_array_create/size/loadAt/storeAt/exchangeAt/compareAndSetAt/compareAndExchangeAt/fetchAndUpdateAt/fetchAndAddAt/addAndFetchAt/fetchAndIncrementAt/incrementAndFetchAt/fetchAndDecrementAt/decrementAndFetchAt` | `RuntimeAtomic.swift` |
| **MIGRATION-ATOMIC-001** (AtomicLongArray) | 同上 `long` 版 | `RuntimeAtomic.swift` |
| **MIGRATION-ATOMIC-001** (getAndUpdate/updateAndGet) | `kk_atomic_{int,long,bool,ref}_{getAndUpdate,updateAndGet}` | `RuntimeAtomic.swift` |
| **TEST-COL-012** (Set HOF) | `kk_set_{map,forEach,filterNot,mapNotNull,flatMap,count_predicate}` | `RuntimeCollectionHOF.swift` |
| **Flow API 完全実装** | `kk_flow_{count,fold,reduce,emit_with_timestamp}` | `RuntimeCoroutineFlow.swift` |
| **STDLIB-CINTEROP-FN-009/042** | `kk_pinned_get` / `kk_copaque_pointer_{new,address}` / `kk_cpointer_{new,address}` / `kk_cname_{lookup,register}` / `kk_cleaner_clean` | `RuntimeNativeAPI.swift` |
| **MIGRATION-ENC-001** (Base64) | `kk_base64_{encode,encodeToByteArray}_instance` / `kk_base64_withPadding_{default,mime,urlsafe}` | `RuntimeBase64.swift` |
| **数値型変換** | `kk_byte_to_{char,uint,ulong}` / `kk_short_to_{char,uint,ulong}` | `RuntimeNumericCoercion.swift` |
| **Char 演算** | `kk_char_fromCode` / `kk_char_minus` | `RuntimeChar.swift` |
| **coroutine channel** | `kk_channel_is_closed_token` | `RuntimeCoroutineChannel.swift` |
| **lazy not-null** | `kk_check_not_null_lazy` / `kk_require_not_null_lazy` | `RuntimePreconditions.swift` |
| **TimeSource.Monotonic** | `kk_clock_gettime_monotonic_ns` / `kk_clock_monotonic_mark_now` | `RuntimeTime.swift` |
| **kotlin.time.Instant** | `kk_instant_from_epoch_seconds` | `RuntimeTime.swift` |
| **coroutine context** | `kk_context_{get_name,release}` / `kk_exception_handler_invoke` | `RuntimeCoroutineContext.swift` |
| **coroutine scope** | `kk_coroutine_{cancel,name_get}` / `kk_coroutine_scope_{is_active,is_cancelled}` | `RuntimeCoroutine.swift` |
| **MIGRATION-PROP-001** | `kk_delegate_{get,set}_value` / `kk_kproperty_stub_{create_full,is_const,is_lateinit,visibility}` | `RuntimeDelegates.swift` |
| **数値コンパニオン定数** | `kk_double_{max,min}_value` / `kk_double_{nan,negative_infinity,positive_infinity}` / `kk_float_*` 同様 / `kk_int_{max,min}_value` / `kk_long_{max,min}_value` | `RuntimeMath.swift` |
| **FreezableAtomicRef** | `kk_freezable_atomic_ref_{is_frozen,store}` | `RuntimeNativeConcurrentABI.swift` |
| **STDLIB-REFLECT-067** | `kk_kclass_get_arity` | `RuntimeReflection.swift` |
| **Array HOF** | `kk_array_mapNotNull` | `RuntimeCollectionHOFArray.swift` |
| **IO** | `kk_output_stream_bufferedWriter_default` | `RuntimeFileIO.swift` |
| **Platform** | `kk_platform_isDebugBinary` | `RuntimePlatform.swift` |
| **GC global root** | `kk_register_global_root` / `kk_unregister_global_root` | `RuntimeGC.swift` |
| **String HOF** | `kk_string_joinToString` | `RuntimeStringHOF.swift` |
| **MIGRATION-RANGE-003** | `kk_ulong_downTo` | `RuntimeRangeUIntULongRange.swift` |
| **URI / URL** | `kk_url_{decode,encode}` | `RuntimeNetwork.swift` |

## C. 参照ゼロの Swift 関数（6 個）→ RF-DEAD-003 ✅ 削除済み

| 関数 | 場所 | 備考 |
|---|---|---|
| `buildBoolCondition` | `Sources/CompilerCore/Codegen/NativeEmitter+FunctionEmission.swift:331` | メソッド内ローカル関数。宣言のみで未呼び出し |
| `collectionHOFRuntimeLinkNames`（複数形） | `Sources/RuntimeABI/StdlibSurfaceSpec.swift:127` | 単数形 `collectionHOFRuntimeLinkName` のみ使用されている |
| `DocumentStore.allURIs` | `Sources/LSPServer/DocumentStore.swift:67` | LSP 内部からも未使用 |
| `PositionResolver.enclosingDecl` | `Sources/LSPServer/PositionResolver.swift:39` | LSP 内部からも未使用 |
| `runtimeRetainObjectHandle` | `Sources/Runtime/RuntimeCollectionHelpers.swift:528` | 同等処理は各所がインライン実装 |
| `runtimeParallelStreamElements` | `Sources/Runtime/RuntimeParallel.swift:50` | private ラッパーの非 private 重複 |

## 偽陽性として除外したもの（参考）

- `RuntimeHTTPRedirectDelegate.urlSession(_:task:willPerformHTTPRedirection:...)` — `URLSessionTaskDelegate` 準拠。Foundation が呼ぶ
- `GoldenHarnessWorkerMain` — `Sources/GoldenHarnessWorker/main.swift` の実行ターゲットエントリポイント
- `kk_match_result_destructured_component1`〜`9` — `HeaderHelpers+SyntheticRegexStubs.swift:448` の文字列補間で emit される
- `_kswiftkRuntimeAutolinkAnchor`（`LinkPhase.swift`）— Foundation/Dispatch シンボルを強制リンクするためのアンカー（意図的な未呼び出し）

## D. テストのみ参照 Swift シンボル → DEADCODE-013 ✅ トリアージ済み

2026-07-02 に `TODO.md` の DEADCODE-013 候補を現 HEAD で再確認した。下記の製品コード上のテスト専用シンボルは削除、または Tests 側へ移動した。

| 判定 | シンボル | 処置 |
|---|---|---|
| 削除 | `KotlinParser.canStartTypeArguments(after:)` overloads | 製品コードから削除。テストは製品コードも使う `canStartTypeArgumentsInternal(hasAnchorToken:)` と parse 経路で維持 |
| 削除 | `SymbolTable.setTypeParameterUpperBound` | 単数 setter を削除。テスト/呼び出し側は `setTypeParameterUpperBounds` に統一 |
| 削除 | `RuntimeMetadataCodec` | JSON wrapper を削除。テストは `JSONEncoder` / `JSONDecoder` で metadata model の Codable round-trip を直接検証 |
| 削除 | `RuntimeMemoryLeakReport` / `runtimeDetectMemoryLeak` | Runtime API として未配線の leak detector を削除。公開 memory metrics テストのみ残す |
| 削除 | `RuntimeJobHandle.completeCancellationIfNeeded` | テスト専用 terminal transition helper を削除。テストは cancellation 後の `complete(with:)` 経路で terminal state を検証 |
| 削除 | `RuntimeABIExterns.externDecl` | テスト内の `allExterns` 辞書 lookup に置換。製品側 lookup cache は削除 |
| Tests へ移動 | `RuntimeReflectionMetadataDecoder` | Reflection metadata round-trip 検証用 decoder として `RuntimeReflectionMetadataEmitterTests` 内の private helper に移動 |

現 HEAD では、DEADCODE-013 の元リストのうち以下は既に存在しない、または名称が変わっており、追加処置なしとした。

```
PhaseTimer.exportTSV / exportJSON
KotlinLanguageVersion / CompilerVersion
BlockScope / validateExpectActualLinks / hasContractReturnsNotNull
smartCastTypeForWhenSubjectCase
DataFlow.invalidateVariable / DataFlow.narrowToNonNull
IncrementalCompilationCache.clearCache
SemaCacheContext.invalidateScope
FileFingerprint.mtimeUnchanged
DependencyGraph.clearFile
compilerPluginMetadata
```

なお `KotlinParser.canStartTypeArgumentsInternal(hasAnchorToken:)` は parser 本体（declaration parsing）から使用されるため dead ではない。`RuntimeABIExterns.allExterns` は ABI parity の canonical extern view として残した。
