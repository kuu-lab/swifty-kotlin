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

## 保持するもの（意図的）— B 14 件

| 理由コード | シンボル | 保持する理由 |
|---|---|---|
| `DEAD-CDECL-TEST-HOOK` | `__kk_gc_mutator_blocking_begin`, `__kk_gc_mutator_blocking_end`, `kk_assertions_reset`, `kk_debugging_gc_suspend_count`, `kk_debugging_global_object_count`, `kk_debugging_thread_count`, `kk_gc_shadow_depth`, `kk_pop_frame`, `kk_push_frame`, `kk_register_frame_map`, `kk_store_frame_root`, `kk_runtime_force_reset`, `kk_runtime_heap_object_count`, `kk_transfer_object` | Runtime のグローバル状態・GC フレーム・転送状態を RuntimeTests から直接操作・検査する hook。 |

`DEAD-CDECL-TEST-HOOK` は各宣言に付記済み。

## 未処置

前回までの増分のうち後継経路が確認できたもの（旧 C bridge 9 件）は `RuntimeABISpec` の登録ごと削除済み。残りは配線の担当確認待ち。

| シンボル | 区分 | 経緯 | 見立て |
|---|---|---|---|
| `__kk_class_get_name` | B | #9114（KUU-2357）で JVM lambda の enclosing class メタデータ用に追加。compiler の emit 経路はまだ無い。 | 配線待ちの可能性。担当を確認してから判断。 |
