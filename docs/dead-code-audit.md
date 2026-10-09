# Dead Code Audit（2026-06-12）

> **現行結果（KUU-1658、2026-10-09）**: Runtime `@_cdecl` export 1,918 件、compiler-unreachable 96 件（A=39 / B=11 / runtime-internal-only=46）。B の意図的 test hook 11 件は理由コード付きで保持し、残り 96 export は C ABI と `RuntimeABISpec` から除去した。元の Issue 基準コミット `99684db9d88f` では B=105。現 HEAD では `kk_duration_toString` と `kk_is_frozen` が追加され B=107 になっていたため、107 件すべてを分類して処置した。

## 継続監査（KUU-1658、2026-10-09）

Issue 作成時点の `99684db9d88f` で `bash Scripts/dead_code_audit.sh --self-test` を再実行し、B=105 を再現した。監査を開始した HEAD `2eb589e33c` では B=107 で、追加分は `kk_duration_toString` と `kk_is_frozen`。両方を含む現行 107 件を次の 3 区分で全件分類した。

### 意図的 test hook — 11 件、C export を保持

これらは Runtime のグローバル状態、GC フレーム、転送状態を Swift RuntimeTests から直接操作・検査するための hook。宣言に `DEAD-CDECL-TEST-HOOK` と理由コードを記した。

```
kk_assertions_reset
kk_assertions_set_enabled
kk_debugging_gc_suspend_count
kk_debugging_global_object_count
kk_debugging_thread_count
kk_pop_frame
kk_push_frame
kk_register_frame_map
kk_runtime_force_reset
kk_runtime_heap_object_count
kk_transfer_object
```

### 削除可能 — source-backed または emitter の置換経路がある 46 件

Kotlin 側の処理は Kotlin source / intrinsic / 現行の別 link name が所有しており、次の旧 C export は不要。関数本体は Swift RuntimeTests の直接テスト用に残し、`@_cdecl` と `RuntimeABISpec` 登録を削除した。

```
__kk_flow_count
__kk_flow_fold
__kk_flow_reduce
__kk_mutable_collection_addAll_checked
__kk_mutable_collection_clear
__kk_mutable_collection_clear_checked
__kk_mutable_collection_remove
__kk_mutable_collection_removeAll
__kk_mutable_collection_removeAll_checked
__kk_mutable_collection_remove_checked
__kk_mutable_collection_retainAll
__kk_mutable_collection_retainAll_checked
__kk_string_toBigDecimalOrNull_flat
__kk_time_mark_from_reading_nanos
__kk_time_mark_reading_nanos
kk_byte_to_char
kk_byte_to_uint
kk_byte_to_ulong
kk_channel_close_cause
kk_dispatcher_default
kk_dispatcher_io
kk_double_max_value
kk_double_min_value
kk_double_nan
kk_double_negative_infinity
kk_double_positive_infinity
kk_duration_absoluteValue
kk_duration_compareTo
kk_duration_div_duration
kk_duration_div_int
kk_duration_infinite
kk_duration_isInfinite
kk_duration_isNegative
kk_duration_minus
kk_duration_times_int
kk_duration_toDuration_double
kk_duration_toDuration_int
kk_duration_toString
kk_duration_unary_minus
kk_sequence_from_list
kk_short_to_char
kk_short_to_uint
kk_short_to_ulong
kk_string_equals
kk_string_get
kk_string_getOrNull
```

判定根拠: `kotlinx.coroutines.flow/Flow.kt` は count/fold/reduce を含む Flow operator を Kotlin source で合成する。`kotlin.collections/MutableCollection.kt` は `_throwing` bridge を使い、旧 collection bridge を呼ばない。`kotlin.time/Duration.kt` は演算・変換・文字列化・定数を Kotlin source で実装し、TimeMark の算術も source に移行済み。Channel close cause は `__kk_channel_close_cause`、Dispatcher default/io は `__kk_dispatcher_named`、String の equals/get/getOrNull は `__kk_string_*_flat`、BigDecimal nullable parse は非 flat ABI を使う。数値変換と Double 定数は compiler の変換・定数経路が所有する。

### 未配線 export — 50 件、C ABI を削除

現行の bundled Kotlin source / CompilerCore / CompilerBackend に emit 経路がなく、RuntimeTests の Swift 直接呼び出しだけが参照していた。HTTP bridge 群を含め、C export と `RuntimeABISpec` 登録を外した。Swift 関数本体と RuntimeTests は残し、Kotlin 側 consumer を追加する際に必要な ABI だけ再導入できる状態にした。

```
__kk_flow_emit_with_timestamp
__kk_kclass_get_arity
__kk_select_receive_value
kk_any_to_string_nullable
kk_char_isUnicodeIdentifierPart
kk_char_minus
kk_cleaner_clean
kk_cleaner_dispose
kk_clock_gettime_monotonic_ns
kk_clock_monotonic_mark_now
kk_cname_lookup
kk_cname_register
kk_context_get_name
kk_context_release
kk_coroutine_cancel
kk_coroutine_scope_is_cancelled
kk_coroutine_scope_register_child
kk_exception_handler_invoke
kk_exception_handler_new
kk_flat_string_release
kk_foundation_date_to_kotlin_instant
kk_future_is_ready
kk_http_body_handlers_ofString
kk_http_body_publishers_ofString
kk_http_client_addTrustedRedirectOrigin
kk_http_client_newHttpClient
kk_http_client_send
kk_http_client_setBearerToken
kk_http_client_setFollowRedirects
kk_http_client_setMaxResponseBodyBytes
kk_http_headers_firstValue
kk_http_headers_map
kk_http_request_builder_GET
kk_http_request_builder_POST
kk_http_request_builder_build
kk_http_request_builder_header
kk_http_request_builder_uri
kk_http_request_newBuilder
kk_http_request_newBuilder_uri
kk_http_response_body
kk_http_response_headers
kk_http_response_statusCode
kk_instant_to_epoch_millis
kk_instant_to_foundation_date
kk_is_frozen
kk_job_is_failed
kk_kxmini_launch_with_exception_handler
kk_object_release
kk_register_global_root
kk_unregister_global_root
```

`RuntimeABISpec` 登録だけでは production use の根拠にならない。RuntimeABISpec は export の型・ABI ミラーなので、consumer が無いものは本線接続済みとはみなさない。`kk_register_global_root` / `kk_unregister_global_root` は将来の Kotlin global-root emission 用として以前は export されていたが、現行 emitter に呼び出しが無いため、Swift test helper として本体を残して C export を外した。

検証: `swift build` は成功。`ABIMismatchRuntimeExportParityTests`（5件）、`RuntimeABISpecVersionTests`、`RuntimeABISyntheticStubTests`、`RuntimeABIExternalLinkValidationTests`（8件）、監査 self-test（5/5）は PASS。処置後は Runtime export 1,918、compiler-unreachable 96、A=39、B=11。残った B は上記 test hook だけ。`kk_exception_handler_invoke` のコメントだけの Runtime 参照を検証する self-test fixture は、同じ分類条件を確認する retained hook `kk_transfer_object` に置き換えた。`--filter RuntimeTests --no-parallel` は `RuntimeCoroutineStateTests.testPlainFunctionInvokeDrivesSuspendingBoxToCompletion` の RuntimeEventLoop 待ちで進まず中断した。別に `--filter RuntimeCoroutineStateTests --no-parallel` を走らせた際も `testJobJoinWithinScopeAndScopeWaitsForChild` の job join 待ちで停止した。両ケースは単独実行では PASS したが、RuntimeTests 全体は未完了。

> **ステータス**: Section A（完全到達不能 102 個）と Section C（参照ゼロ Swift 関数 6 個）は **削除済み**。
> 参照元ファイル（`RuntimeLogging.swift`, `RuntimeFlowErrorHandling.swift` 等）も既に存在しない。
> Section B（テストのみ参照 120 個）はトリアージ完了（2026-06-23 実施）。RF-DEAD-002 結果参照。
> Section D（テストのみ参照 Swift シンボル）はトリアージ完了（2026-07-02 実施）。DEADCODE-013 結果参照。
> 本ドキュメントは監査の履歴記録として保持する。

TODO.md の Phase RF9（RF-DEAD-001〜004）の根拠インベントリ。検出手法と全リストを記録する。

## 継続監査（DEADCODE-014、2026-09-16）

現行 HEAD（`ec7eb414c`）で `Scripts/dead_code_audit.sh --self-test` を再実行した。
監査スクリプトは、`@_cdecl("__kk_x")` と Swift 関数名 `kk_x` が異なる Runtime
エクスポートについて、Tests と Runtime 内部の Swift 名呼び出しも cdecl 名へ写像する。
これにより `__kk_mutable_map_iterator_*` などの別名呼び出しを誤って完全到達不能と
分類しない。実行前の集計は Runtime export 1,678 件、compiler-unreachable 147 件、
A 25 件、B 82 件だった。

今回、source-backed 化後に E0（compiler / Tests / Runtime 内部の参照が 0）を満たす
次の 11 export と対応する `RuntimeABISpec` エントリを削除した。

```
__kk_kfunction_get_name __kk_kfunction_get_arity __kk_kfunction_get_return_type
kk_callable_ref_name kk_callable_ref_arity kk_callable_ref_is_suspend kk_callable_ref_parameters
__kk_kproperty_stub_name __kk_kproperty_stub_return_type
kk_indexed_value_new __kk_mutable_collection_addAll_sequence
```

削除後の再実行では Runtime export 1,667 件、compiler-unreachable 136 件、A 14 件、
B 82 件となり、セルフテスト（静的 emit、2 段階 prefix、fatalError 自己言及、Swift 名
別名呼び出し）は全て PASS した。

KCallable の共通 `name` / `returnType` bridge、callable-reference の tag / call、
KProperty stub の create、`IndexedValue` の Kotlin data class、MutableCollection の
Sequence 拡張は引き続き実働経路として保持している。残る A 候補（KProperty の完全
メタデータ拡張、`kk_cinterop_writeBits`、HTTP の追加設定・応答メタデータ）は、
それぞれ MIGRATION-PROP-001、STDLIB-CINTEROP-FN-046、HTTP surface の所有タスクで
扱うため今回の削除対象から除外した。

## 継続監査（DEADCODE-014、2026-09-23）

現行 HEAD（`59dd246ff`）で `Scripts/dead_code_audit.sh --self-test` を再実行し、
#6881 マージコミット（`a3f3a4b12`、2026-09-16 後状態）の worktree で同じ監査を
再現してリスト差分を取った。

| 指標 | 2026-09-16 (#6881) | 2026-09-23 (HEAD) |
|---|---|---|
| Runtime `@_cdecl` export | 1,665 | 1,702（+78 追加 / −41 削除） |
| compiler-unreachable | 136 | 130 |
| A: 完全到達不能 | 14 | 14（変化なし） |
| B: テストのみ | 82 | 76（−7 +1） |
| runtime-internal のみ | 40 | 40（変化なし） |

self-test は 4/4 PASS。セルフテスト fixture の既知誤分類（静的 emit、2 段階
prefix、fatalError 自己言及、Swift 名別名）はいずれも再発していない。

**B 減少の内訳**（全て source-backed 移行または本線配線による正当な減少）:

- `kk_freezable_atomic_ref_{load,store,compareAndSet,compareAndSwap,is_frozen}` —
  #6914 で FreezableAtomicReference が Kotlin ソース実装へ移行し、bridge・spec・
  テストごと削除
- `kk_cpointer_new` — DetachedObjectGraph 実装（#6893）で compiler emit 経路へ配線
- `kk_instant_from_epoch_seconds` — kotlin.time stdlib API（#6932）で同様に配線

**B 増加**: `kk_object_release`（#7039、ARCH-016）。retained box の明示解放
オーナーとして新設され、compiler emit 側の配線待ちで意図的にテストのみの状態。

**A 候補 14 件の見直し** — いずれも前回の延期理由が現行 HEAD で再確認でき、
本サイクルも削除しない:

- `__kk_kproperty_stub_{create_full,is_const,is_lateinit,visibility}` — bundled
  stdlib に KProperty 系（`kotlin/KProperty*.kt`・`properties/Delegates.kt`）は
  存在するが、完全メタデータ（isConst / isLateinit / visibility）の Kotlin 側
  消費者が未実装。MIGRATION-PROP 系作業で配線予定のまま
- `kk_cinterop_writeBits` — `kotlinx.cinterop` は `StableRef.kt` のみで
  `writeBits` 消費 API が未実装（STDLIB-CINTEROP-FN 系の後続タスク待ち）
- `kk_http_*` 9 件 — `RuntimeNetwork.swift` の HTTP クライアントは Linear で
  現在有効なセキュリティ改善対象（KUU-805/817）として所有されている surface。
  Kotlin 側 HTTP stdlib がまだ無く、新規 stdlib 配線時に必要になる設定・
  応答メタデータ関数のため保持

**他監査軸の再確認**:

- tracked `.c/.h/.cc/.cpp` — 2 件（`Sources/RuntimeCAtomics/`）。#7121 で
  kotlin.concurrent.Atomic* の NSLock ストレージを C `stdatomic` セルへ置換した
  SwiftPM C ターゲット。`kkrt_atomic_*` は `static inline` のため本監査の
  `@_cdecl` 範囲外だが dead ではない
- `DiagnosticRegistry` — 現行 99 descriptor、全て Sources 内に production
  発行箇所あり（発行 0 のコードなし）
- `SKIP-DIFF (DEBT-DIFF-007)` — 10 タグ（2026-09-16 計測と同数、DEBT-DIFF-007 の
  所有タスクで継続中）

## 継続監査（DEADCODE-014、2026-10-05）

分岐元 `fc977cd93` と前回監査基準 `59dd246ff` を再監査した。Runtime 内部参照の
集計が `//` / `///` の関数名まで使用として扱っていたため、コメントだけの行を
除外した。`kk_exception_handler_invoke` が runtime-internal ではなく B に入る
セルフテストを追加し、既存の Swift 名別名呼び出しの検証も保持した。

| 指標 | 前回（旧集計） | 前回（コメント補正） | 今回（削除前・補正済み） | 今回（削除後） |
|---|---:|---:|---:|---:|
| Runtime `@_cdecl` export | 1,702 | 1,702 | 1,800 | 1,797 |
| compiler-unreachable | 130 | 130 | 140 | 137 |
| A: 完全到達不能候補 | 14 | 17 | 19 | 16 |
| B: テストのみ | 76 | 81 | 86 | 86 |
| runtime-internal のみ（A/B と排他的） | 40 | 32 | 35 | 35 |

旧集計のままなら今回削除前は A 14 / B 79 / runtime-internal 47 だった。
補正は compiler-unreachable の総数を変えず、その内訳のみを訂正する。
これは字句参照による保守的な候補抽出であり、動的 prefix の過大一致や
インラインコメント・文字列の参照は残り得る。A を無条件の削除リストとして
扱わず、consumer と所有タスクを個別に確認する。

**今回削除した E0 bridge（3 件）** — compiler / Tests / Runtime の実呼び出しが
なく、現行の Kotlin 実装に後継経路がある。対応する `RuntimeABISpec` も削除した:

- `__kk_string_builder_append_range` — `kotlin/text/StringBuilder.kt` の
  `appendRange(CharSequence, startIndex, endIndex)` は source-backed な
  `appendCharSequenceRange` を経由し、CharArray を作って
  `__kk_string_builder_append_char_array` を呼ぶ。CharArray 用 bridge は保持。
  `buildstring_appendrange.kt` に StringBuilder を CharSequence として渡すケース、
  自己追記、空範囲、UTF-16 サロゲートの範囲切り出し、不正範囲の回帰を追加した。
- `kk_job_invoke_on_completion` / `kk_job_dispose_completion_handler` —
  `kotlinx/coroutines/Job.kt` は既に `__kk_job_invoke_on_completion`（5 引数）と
  `__kk_job_dispose_handle` を使う。削除対象は呼び出し元のない旧 wrapper のみで、
  handler 登録・dispose の実装は保持した。

**前回との差分（同じコメント補正後の分類で比較）**:

- A: `kk_http_client_setBearerToken` がテスト追加により B へ移動。今回削除した
  3 bridge は前回 A に無く、残る 16 件は前回の候補と同じ。
- B: `__kk_select_receive_value`、`kk_channel_close_cause`、`kk_dispatcher_io`、
  `kk_flat_string_release`、`kk_http_client_addTrustedRedirectOrigin`、
  `kk_http_client_setBearerToken`、`kk_http_client_setMaxResponseBodyBytes` が追加。
  `kk_atomic_long_compareAndSet` と `kk_cpointer_address` は compiler-reachable
  へ移動（+7 / −2）。
- runtime-internal のみ: `__kk_mutable_map_entry_setValue`、`kk_string_from_utf8`、
  `kk_worker_new` が追加（+3）。

**残る A 16 件の扱い**:

- KProperty の完全メタデータ 4 件と `kk_cinterop_writeBits` は、前回同様
  MIGRATION-PROP / STDLIB-CINTEROP-FN の後続 surface 配線対象として保持。
- HTTP の追加設定・応答メタデータ 8 件は `RuntimeNetwork.swift` の surface
  として保持。前回記録の KUU-805 / KUU-817 は現在 Done・archived であり、
  「進行中のセキュリティ修正」を保持理由にはしない。Kotlin HTTP surface の
  未配線候補として、今回の限定的な bridge 整理とは分離する。
- `__kk_iterator_builder_hasNext_coro` / `__kk_iterator_builder_next_coro` /
  `kk_sequence_completed_sentinel` はコメント除外で A と判明した 3 件。
  `RuntimeSequenceBuilders.swift` が明示する CORO-004 Phase 2 の将来 compiler
  consumer 用 API で、現行の blocking iterator 経路とは別契約。
  suspension-aware iterator の配線／撤去判断を要するため今回は保持する。

**他監査軸**:

- tracked `.c/.h/.cc/.cpp`: 2 件。`RuntimeCAtomics.c` と
  `include/RuntimeCAtomics.h` は使用中の SwiftPM C ターゲットで、削除候補なし。
- `DiagnosticRegistry`: 132 unique descriptor。全コードについて registry 外の
  `Sources` に参照があり、参照ゼロの descriptor はない。発行には直接の
  `error` / `warning` に加え、parser の missing-token、診断コード変数、
  DiagnosticEngine の fallback / truncation など間接経路も含まれる。
  この監査は静的な発行経路確認であり、全診断を実際に発火させる試験ではない。
- active `SKIP-DIFF`: 122 タグ / 122 ファイル。DEBT-DIFF-001 は 117、007 は 2、
  009 / 010 / 011 は各 1。KSP-959 の internal `@PublishedApi` helper ケースは
  skip を維持したまま DEBT-DIFF-001 へ正規化した。全 skipped ケースの
  `--force-run-skipped` 再実行は今回行わず、skip 理由と debt ID は各ケースの directive に記録されている。

再現: `bash Scripts/dead_code_audit.sh --self-test --output-dir <audit-dir>`。
5/5 fixture が PASS。比較時は `59dd246ff` の worktree にも同じコメント除外を
適用し、`runtime_cdecl.txt` / `kk_candidates.txt` / `dead_A.txt` / `dead_B.txt` を比較した。

検証: `swift build`、Runtime ABI link 6 件、String synthetic member link 4 件、
StringBuilder / Job completion の Runtime 19 件が PASS。
`buildstring_appendrange.kt` は kotlinc 2.3.10 との native 出力比較も PASS。
既存の `coroutine_job_invoke_on_completion.kt` と
`kotlinx_coroutines_job_callback_completion.kt` は callback 内でクラッシュした。
捕捉付き callback の最小再現は未変更の分岐元 `fc977cd93` を別 worktree で
ビルドした compiler / Runtime でも同じ panic になり、共通 callback ABI の
既存不具合として [KUU-1194](https://linear.app/kuu/issue/KUU-1194/jobinvokeoncompletion-の捕捉付き-callback-が-mutable-cell-を失い-native)
で追跡する。失敗ケースは無効化しておらず、Job の diff 比較は未通過。
全 Swift test / Golden / diff corpus はローカルでは未実行。

## 継続監査（KUU-1657、2026-10-09）

現行 HEAD（`2eb589e33`）で `Scripts/dead_code_audit.sh --self-test` を実行し、
Category A の39候補を全件照合した。監査スクリプトの動的リンク認識を補正し、
source-backed 化済み ABI 3 件と、現行 consumer がない ABI 1 件を実装と `RuntimeABISpec` から削除した。

| 指標 | 修正前 | 修正後 |
|---|---:|---:|
| Runtime `@_cdecl` export | 2,014 | 2,010 |
| compiler-unreachable | 192 | 167 |
| A: 完全到達不能候補 | 39 | 14 |
| B: テストのみ | 107 | 107 |
| runtime-internal のみ | 46 | 46 |

**CVariable の誤検知 21 件** — 以下の全シンボルはコンパイラ到達可能で、Runtime ABI からは削除しない。

```
kk_cvar_bool_store kk_cvar_byte_store kk_cvar_cpointer_store
kk_cvar_double_load kk_cvar_double_store kk_cvar_float_load kk_cvar_float_store
kk_cvar_int_load kk_cvar_int_store kk_cvar_long_load kk_cvar_long_store
kk_cvar_short_load kk_cvar_short_store kk_cvar_ubyte_load kk_cvar_ubyte_store
kk_cvar_uint_load kk_cvar_uint_store kk_cvar_ulong_load kk_cvar_ulong_store
kk_cvar_ushort_load kk_cvar_ushort_store
```

`HeaderHelpers+SyntheticCInteropStubs.swift` の `primitiveVarKinds` が link prefix を
タプル値として保持し、`registerAtomicValueProperty` が prefix + `_load` を getter link
として登録する。`CallLowerer+MemberPropertyReads.swift` はその getter を呼び出し、
`CallLowerer+MemberAssignment.swift` は同じ synthetic property の代入を `_load` から
`_store` へ導出する。旧監査はタプル内の prefix 値とこの導出規則を関連付けず、これらを
A に誤分類していた。prefix を明示したタプルラベルと、導出 store link の監査・self-test
を追加した。実行時の self-test は 8/8 PASS。

**実装と spec を削除した ABI 4 件（source-backed 3 件、現行 consumer のない ABI 1 件）**:

- `__kk_comparable_time_mark_from_reading_nanos` — 現行 `TimeSource.kt` / `TimeSources.kt`
  は `ValueTimeMark` / `AbstractLongTimeMark` / `AbstractDoubleTimeMark` を Kotlin 側で
  構築する。専用 Runtime factory と、その factory だけが使っていた itable 登録 helper を削除。
- `__kk_string_format_locale` — 旧 boxed-string ABI。bundled `StringFormat.kt` は
  `__kk_string_format_locale_flat` を指定しており、Runtime の flat-return 実装だけを保持。
- `kk_duration_isPositive` — bundled `Duration.isPositive()` は `rawValue > 0L` を
  Kotlin ソースで評価する。Runtime bridge と BridgeCoverage spec を削除。
- `kk_native_ptr_of` — 現行 Kotlin source / Sema / KIR に宣言・emit 経路も consumer もない。
  他の NativePtr 操作には別々の経路があるため、この孤立 factory だけを Runtime bridge と
  ABI parity spec から削除。

**理由コードを付けて保持する14件**:

| 理由コード | シンボル | 根拠 |
|---|---|---|
| `MIGRATION-PROP-001` | `__kk_kproperty_stub_create_full`, `__kk_kproperty_stub_visibility` | KProperty 完全メタデータの Kotlin consumer はまだない。 |
| `STDLIB-CINTEROP-FN-046` | `kk_cinterop_writeBits` | writeBits の Runtime 実装はあるが bundled Kotlin consumer が未実装。 |
| `HTTP-SURFACE-PENDING-001` | `kk_http_body_publishers_noBody`, `kk_http_client_setConnectTimeoutMillis`, `kk_http_client_setReadTimeoutMillis`, `kk_http_response_errorMessage`, `kk_http_response_header`, `kk_http_response_isSuccessful`, `kk_http_response_timedOut`, `kk_http_response_url` | Kotlin HTTP facade がなく未配線。KUU-805 / KUU-817 は Done・archived で現 owner ではないため、HTTP surface の後続 owner は未割当として明記する。 |
| `CORO-004-PHASE-2` | `__kk_iterator_builder_hasNext_coro`, `__kk_iterator_builder_next_coro`, `kk_sequence_completed_sentinel` | suspension-aware sequence consumer が未配線。Runtime のコメントと ABI spec が Phase 2 用途を明記。 |

最終 A=14 は前回ベースライン16以下。監査結果の再現は
`bash Scripts/dead_code_audit.sh --self-test --output-dir <audit-dir>`。

検証: `swift build` PASS、`bash Scripts/validate_runtime_abi_links.sh --no-parallel`
8/8 PASS、`RuntimeExperimentalTimeTests` PASS、`RuntimeStringArrayTests` PASS。
`RuntimeDurationTests` は `testNullableParsersReturnTaggedLongPayloads` の16 assertion
が失敗した。このテストは nullable `Long` を返す parse bridge の直値に
`kotlin.time.Duration` type ID を期待するが、bundled `Duration.kt` はその `Long?` を
`Duration(it)` で包む。今回削除した `kk_duration_isPositive` とは別経路。

完了条件の `RuntimeTests` 全体は未通過。直列実行は
`RuntimeCoroutineStateTests.testCoroutineScopeLaunchWithContForwardsCaptureArgs` の
`kk_job_join` semaphore wait から進まず、スタックサンプルで停止を確認して中断した。
並列実行でも Runtime isolation timeout と関連のない失敗が出たため、green とは扱わない。

## 検出手法

識別子トークン頻度解析（`Sources` / `Tests` / `Scripts` / `Package.swift` / `*.kt` 横断）で「宣言されているが参照ゼロ」のシンボルを抽出し、以下の到達経路を順に除外して確定した。

1. **静的 emit**: CompilerCore 内の `kk_*` 文字列リテラル参照
2. **動的 emit（文字列補間）**: `"kk_xxx_\(...)"` 形式 25 プレフィックス（`kk_op_` / `kk_range_` / `kk_base64_*_` / `kk_match_result_destructured_component` 等）。前方一致で除外
3. **動的 emit（表駆動）**: `StdlibSurfaceSpec.collectionHOFRuntimeLinkName` 経由の 164 link name（list / set / map / sequence の HOF。`array` は対象外）
4. **テスト参照**: `Tests/` からの直接呼び出し（語境界一致。superstring 誤検知に注意: `kk_http_client_post` は `kk_http_client_post_async` とは別物）。`@_cdecl("__kk_x")` の Swift 名別名も照合
5. **Runtime 内部呼び出し**: 他のランタイム関数からの Swift レベル呼び出し（cdecl 名と Swift 名の別名も照合）
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
kk_char_minus
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
| **STDLIB-CINTEROP-FN-009/042** | ~~`kk_pinned_get`~~（2026-07-10 訂正: `HeaderHelpers+SyntheticCInteropStubs.swift` で externalLinkName 配線済み — 本表から除外） / `kk_copaque_pointer_{new,address}` / `kk_cpointer_{new,address}` / `kk_cname_{lookup,register}` / `kk_cleaner_clean` | `RuntimeNativeAPI.swift` |
| **MIGRATION-ENC-001** (Base64) | `kk_base64_{encode,encodeToByteArray}_instance` / `kk_base64_withPadding_{default,mime,urlsafe}` | `RuntimeBase64.swift` |
| **数値型変換** | `kk_byte_to_{char,uint,ulong}` / `kk_short_to_{char,uint,ulong}` | `RuntimeNumericCoercion.swift` |
| **Char 演算** | `kk_char_minus` | `RuntimeChar.swift` |
| **coroutine channel** | `kk_channel_is_closed_token` | `RuntimeCoroutineChannel.swift` |
| **lazy not-null** | `kk_check_not_null_lazy` / `kk_require_not_null_lazy` | `RuntimePreconditions.swift` |
| **TimeSource.Monotonic** | `kk_clock_gettime_monotonic_ns` / `kk_clock_monotonic_mark_now` | `RuntimeTime.swift` |
| **kotlin.time.Instant** | `kk_instant_from_epoch_seconds` | `RuntimeTime.swift` |
| **coroutine context** | `kk_context_{get_name,release}` / `kk_exception_handler_invoke` | `RuntimeCoroutineContext.swift` |
| **coroutine scope** | `kk_coroutine_{cancel,name_get}` / `kk_coroutine_scope_{is_active,is_cancelled}` | `RuntimeCoroutine.swift` |
| **MIGRATION-PROP-001** | `kk_delegate_{get,set}_value` / `kk_kproperty_stub_{create_full,is_const,is_lateinit,visibility}` | `RuntimeDelegates.swift` |
| **数値コンパニオン定数** | `kk_double_{max,min}_value` / `kk_double_{nan,negative_infinity,positive_infinity}` / `kk_float_*` 同様 / `kk_int_{max,min}_value` / `kk_long_{max,min}_value` | `RuntimeMath.swift` |
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
