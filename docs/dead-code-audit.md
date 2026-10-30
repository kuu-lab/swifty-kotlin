# Dead Code Audit

Runtime が `@_cdecl` で公開する `kk_*` / `__kk_*` のうち、コンパイラが emit できず Kotlin プログラムから呼べないものの台帳。件数と一覧は `Scripts/dead_code_audit.sh` の出力が正で、この文書は **スクリプトからは分からない判断（なぜ残すか、後継は何か）** だけを持つ。過去の経緯は git で追う（履歴付きの最終版: `git show 209eca2f97:docs/dead-code-audit.md`）。

再現: `bash Scripts/dead_code_audit.sh --self-test --output-dir <dir>`（毎晩 `.github/workflows/nightly-full.yml` の `audits` ジョブが実行）

## 現在の状態（2026-10-19、旧 C bridge 9 件の削除後）

| 指標 | 件数 | 意味 |
|---|---:|---|
| Runtime `@_cdecl` | 2,072 | |
| compiler-unreachable | 74 | A + B + runtime-internal-only |
| A | 14 | compiler・Tests・Runtime 内部のどこからも参照なし |
| B | 11 | Tests からのみ参照（保持 10 件 + 未処置の `__kk_class_get_name`） |
| runtime-internal-only | 49 | Runtime 内部からのみ参照（A/B と排他。対象外） |

A / B は字句参照による保守的な抽出で、動的 prefix の過大一致やコメント・文字列の取りこぼしが残り得る。A を無条件の削除リストにせず、後継経路と担当を確認してから消す。`RuntimeABISpec` への登録は export の型ミラーであり、使用の証拠ではない。

## 保持するもの（意図的）— A 14 件・B 10 件

| 理由コード | シンボル | 保持する理由 |
|---|---|---|
| `MIGRATION-PROP-001` | `__kk_kproperty_stub_create_full`, `__kk_kproperty_stub_visibility` | KProperty 完全メタデータの Kotlin 側 consumer が未実装。 |
| `STDLIB-CINTEROP-FN-046` | `kk_cinterop_writeBits` | Runtime 実装はあるが、bundled Kotlin の consumer が未実装。 |
| `HTTP-SURFACE-PENDING-001` | `kk_http_body_publishers_noBody`, `kk_http_client_setConnectTimeoutMillis`, `kk_http_client_setReadTimeoutMillis`, `kk_http_response_errorMessage`, `kk_http_response_header`, `kk_http_response_isSuccessful`, `kk_http_response_timedOut`, `kk_http_response_url` | Kotlin HTTP facade が無く未配線。旧 owner の KUU-805 / KUU-817 は Done・archived で、後続 owner は未割当。 |
| `CORO-004-PHASE-2` | `__kk_iterator_builder_hasNext_coro`, `__kk_iterator_builder_next_coro`, `kk_sequence_completed_sentinel` | suspension-aware な sequence consumer が未配線。現行の blocking iterator 経路とは別契約。 |
| `DEAD-CDECL-TEST-HOOK` | `__kk_gc_mutator_blocking_begin`, `__kk_gc_mutator_blocking_end`, `__kk_gc_mutator_enter`, `__kk_gc_mutator_leave`, `__kk_gc_safepoint`, `kk_assertions_reset`, `kk_debugging_gc_suspend_count`, `kk_debugging_global_object_count`, `kk_debugging_thread_count`, `kk_gc_shadow_depth`, `kk_pop_frame`, `kk_push_frame`, `kk_register_frame_map`, `kk_store_frame_root`, `kk_runtime_force_reset`, `kk_runtime_heap_object_count`, `kk_transfer_object` | Runtime のグローバル状態・GC フレーム・転送状態を RuntimeTests から直接操作・検査する hook。 |

`HTTP-SURFACE-PENDING-001` と `CORO-004-PHASE-2` は、この表だけが台帳（宣言側のコメントには同名のコードが無い）。消す・配線する際はこの行も更新する。`DEAD-CDECL-TEST-HOOK` は各宣言に付記済み。

## 未処置

前回までの増分のうち後継経路が確認できたもの（旧 C bridge 9 件）は `RuntimeABISpec` の登録ごと削除済み。残りは配線の担当確認待ち。

| シンボル | 区分 | 経緯 | 見立て |
|---|---|---|---|
| `__kk_class_get_name` | B | #9114（KUU-2357）で JVM lambda の enclosing class メタデータ用に追加。compiler の emit 経路はまだ無い。 | 配線待ちの可能性。担当を確認してから判断。 |
