# ARCH-014: ルート 0 件の frame map emit 停止の決定記録

## 決定

2026-09-11、ARCH-014 は「ルート 0 件の frame map 登録 / push / pop の emit を停止」を採択する。

具体的には、codegen（`NativeEmitter+FunctionEmission.swift`）が全関数プロローグで emit していた `kk_register_frame_map(functionId, 0)` と `kk_push_frame(functionId, 0)`、および全出口で emit していた `kk_pop_frame()` を削除し、対応する weak runtime スタブ定義（`NativeEmitter.swift` の `defineWeakFrameRuntimeStubs`）も削除した。

## 理由（実測）

frame map ポインタは全関数で定数 `0`（root 0 件）であり、runtime 側は呼び出しごとに「GC ロック取得 + 辞書更新 + 配列 append + pop 時の辞書削除」を行うだけで、実際の root 情報は一切登録されていなかった。つまりこの emit は正確さに寄与しない純粋なオーバーヘッドであり、関数呼び出しあたり 3 回のランタイム呼び出しと 2 回のロック取得を常時課していた。

## Runtime ABI の保持

`RuntimeGC.swift` の `kk_register_frame_map` / `kk_push_frame` / `kk_pop_frame` 実装と、`RuntimeABISpec+GC.swift` の spec エントリは**削除しない**。理由は次の 2 点である。

- `RuntimeGCTests.testFrameMapRootsProtectActiveFramePointers` が手動 ABI 経路としてこの API を使っており、frame map 機構そのものの動作は検証済みで保持する価値がある。
- ARCH-016 で GC を実体化する際の再導入口として、runtime 側の ABI を温存する方が再設計コストが小さい。

## 再導入方針（ARCH-016）

GC 実体化時には、グローバルロックを取る辞書方式ではなく、**TLS シャドウスタック**として正規に再導入する。

- codegen が関数ごとの実 root slot を持つ `FrameMapDescriptorC` を構築する。
- push/pop はスレッドローカルなフレームスタック上で行い、グローバルロックを取らない。
- root 列挙は GC がスレッド停止後に TLS スタックを走査する形にする。

この再導入までは、`docs/spec.md` J16.2 の「各関数は compile 時に GC root map を生成し runtime に登録する」は未配線状態である。
