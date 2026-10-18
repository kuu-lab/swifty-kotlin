# Dead Code Audit

Runtime が `@_cdecl` で公開する `kk_*` / `__kk_*` のうち、コンパイラが emit できず Kotlin プログラムから呼べないものの台帳。件数と一覧は `Scripts/dead_code_audit.sh` の出力が正で、この文書は **スクリプトからは分からない判断（なぜ残すか、後継は何か）** だけを持つ。過去の経緯は git で追う（履歴付きの最終版: `git show 209eca2f97:docs/dead-code-audit.md`）。

再現: `bash Scripts/dead_code_audit.sh --self-test --output-dir <dir>`（四半期ごとに `.github/workflows/quarterly-audits.yml` が実行）

## 現在の状態（2026-10-18、`7cbc40991f`）

| 指標 | 件数 | 意味 |
|---|---:|---|
| Runtime `@_cdecl` | 2,081 | |
| compiler-unreachable | 84 | A + B + runtime-internal-only |
| A | 20 | compiler・Tests・Runtime 内部のどこからも参照なし |
| B | 15 | Tests からのみ参照 |
| runtime-internal-only | 49 | Runtime 内部からのみ参照（A/B と排他。対象外） |

A / B は字句参照による保守的な抽出で、動的 prefix の過大一致やコメント・文字列の取りこぼしが残り得る。A を無条件の削除リストにせず、後継経路と担当を確認してから消す。`RuntimeABISpec` への登録は export の型ミラーであり、使用の証拠ではない。

## 保持するもの（意図的）— A 14 件・B 11 件

| 理由コード | シンボル | 保持する理由 |
|---|---|---|
| `MIGRATION-PROP-001` | `__kk_kproperty_stub_create_full`, `__kk_kproperty_stub_visibility` | KProperty 完全メタデータの Kotlin 側 consumer が未実装。 |
| `STDLIB-CINTEROP-FN-046` | `kk_cinterop_writeBits` | Runtime 実装はあるが、bundled Kotlin の consumer が未実装。 |
| `HTTP-SURFACE-PENDING-001` | `kk_http_body_publishers_noBody`, `kk_http_client_setConnectTimeoutMillis`, `kk_http_client_setReadTimeoutMillis`, `kk_http_response_errorMessage`, `kk_http_response_header`, `kk_http_response_isSuccessful`, `kk_http_response_timedOut`, `kk_http_response_url` | Kotlin HTTP facade が無く未配線。旧 owner の KUU-805 / KUU-817 は Done・archived で、後続 owner は未割当。 |
| `CORO-004-PHASE-2` | `__kk_iterator_builder_hasNext_coro`, `__kk_iterator_builder_next_coro`, `kk_sequence_completed_sentinel` | suspension-aware な sequence consumer が未配線。現行の blocking iterator 経路とは別契約。 |
| `DEAD-CDECL-TEST-HOOK` | `kk_assertions_reset`, `kk_assertions_set_enabled`, `kk_debugging_gc_suspend_count`, `kk_debugging_global_object_count`, `kk_debugging_thread_count`, `kk_pop_frame`, `kk_push_frame`, `kk_register_frame_map`, `kk_runtime_force_reset`, `kk_runtime_heap_object_count`, `kk_transfer_object` | Runtime のグローバル状態・GC フレーム・転送状態を RuntimeTests から直接操作・検査する hook。 |

`HTTP-SURFACE-PENDING-001` と `CORO-004-PHASE-2` は、この表だけが台帳（宣言側のコメントには同名のコードが無い）。消す・配線する際はこの行も更新する。`DEAD-CDECL-TEST-HOOK` は各宣言に付記済み。

## 未処置 — 前回記録（A 14 / B 11）から増えた A +6 / B +4

いずれも compiler の emit 経路が後継へ移ったか、新設されて未配線のもの。削除する場合は `RuntimeABISpec` の登録を同時に外し、Swift 本体のテストは後継へ移す。

| シンボル | 区分 | 経緯 | 見立て |
|---|---|---|---|
| `__kk_sequence_input_stream_available`, `__kk_sequence_input_stream_close` | A | #8325 で compiler の link 先が `_throwing` 版へ切り替わった。 | 後継あり。削除候補。 |
| `__kk_io_exception_new`, `_message`, `_message_cause`, `_cause`（4 件） | A | #8325 で bundled Kotlin の `IOException` 宣言（`@KsSymbolName` 付きコンストラクタ 4 件）が消え、`java.io.IOException` は `kotlinx.io.IOException` の typealias になった。 | consumer なし。削除候補。 |
| `__kk_buffered_writer_close`, `__kk_output_stream_close` | B | compiler は `_throwing` 版を使う。旧版は `RuntimeBufferedWriterTests` / `RuntimeStreamTests` だけが呼ぶ。 | 後継あり。削除候補（テストは `_throwing` へ移行）。 |
| `__kk_kclass_find_annotation` | B | compiler は `__kk_kclass_find_annotation_typed` を使う。旧版を参照するのは `ReflectFindAnnotationTests`。 | 後継あり。削除候補（テストの参照形態は要確認）。 |
| `__kk_class_get_name` | B | #9114（KUU-2357）で JVM lambda の enclosing class メタデータ用に追加。compiler の emit 経路はまだ無い。 | 配線待ちの可能性。担当を確認してから判断。 |
