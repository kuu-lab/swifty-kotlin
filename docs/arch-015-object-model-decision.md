# ARCH-015: オブジェクトモデルの決定記録

## 決定

2026-08-26、ARCH-015 は選択肢 B「未配線側を削除し、現行 box モデルに最適化を集中」を採択する。

ここでいう採択は、現行の codegen/runtime の正規経路を `kk_object_new`、Swift ARC box、インスタンス単位の metadata 登録に固定するという意味である。`KTypeInfo`/`kk_alloc`/`KKObjHeader`/managed heap の即時削除はこの decision PR には含めない。`docs/spec.md` J16 がこの ABI を仕様として記載し、RuntimeTests と ABI parity tests が手動到達性を持つため、削除は下記の互換性ゲートを持つ別タスクで行う。

選択の根拠は、将来の理想性能ではなく、現行 master の codegen が B 側だけを生成し、A 側は runtime の手動 API と fallback に留まっていること、そして現在の測定で A 側 fallback が B 側の dictionary hit より速くなっていないことである。

## 対象と非対象

この記録で扱うのは ARCH-015 の設計判断だけである。ARCH-013 の primitive boxing/unboxing 実装、ARCH-016 の release/所有権実装、A または B の dead-code 削除は変更しない。後続作業が安全に着手できるように、必要条件と別タスク案だけを記録する。

## 編集前の到達性監査

監査対象は origin/master `413cf7799ba513166d14b13bba355d9ea1779af5` である。

- `Sources/CompilerCore/KIR/KIRVtableRegistrationLowering.swift` は、オブジェクト生成時に `kk_object_register_vtable_method` と `kk_object_register_itable_*` を出力する。
- `Sources/CompilerCore/KIR/CallLowerer.swift` はオブジェクト生成を `kk_object_new` に接続する。
- `Sources/CompilerBackend/NativeEmitter+FunctionEmission.swift` は virtual/interface call を `kk_vtable_lookup`/`kk_itable_lookup*` 経由の間接 call にする。
- compiler source の `kk_alloc`/`KTypeInfo` 参照は、`CallLowerer+SafeMemberCalls.swift` などの fallback を説明するコメントと layout 同期コメントであり、KTypeInfo の静的テーブルを生成する lowering/emitter ではない。
- `Sources/Runtime/RuntimeGC.swift` は `kk_alloc` で `KKObjHeader` と `heapObjects` を作る。一方 `Sources/Runtime/RuntimeStringArray.swift` と `Sources/Runtime/RuntimeCollectionHelpers.swift` は `RuntimeObjectBox` などを `Unmanaged.passRetained` で `objectPointers` に登録し、registration API でインスタンス辞書を埋める。
- `Sources/Runtime/RuntimeRangeLongRange.swift` の `kk_vtable_lookup` は、最初に metadata lock 下の `objectVtableMethods[object][slot]` を検索し、未登録時だけ `heapObjects` の `KKObjHeader.typeInfo` に fallback する。従って現行の KTypeInfo 経路も lock-free static dispatch ではない。
- `Tests/RuntimeTests/RuntimeGCTests.swift`、`RuntimeNativeRefRuntimeABITests.swift`、`RuntimeThreadLocalTests.swift` と `Tests/RuntimeTests/ABIMismatchTests.swift` は `kk_alloc`/`KTypeInfo` を直接呼ぶ。これは codegen 到達性ではなく、runtime ABI/GC の手動テスト到達性である。

### 再現可能な LLVM 実測

以下を origin/master 上で実行した。ビルドは `swift build --jobs 1`、codegen は既存 fixture を使った。

```text
swift build --jobs 1
.build/debug/kswiftc --emit llvm -o /tmp/arch015-abstract.ll Scripts/diff_cases/abstract_open_override.kt
```

`abstract_open_override.kt` の入力 hash は `9d908a4a0e37882c7936d9dc3918fb63926f0745`。生成 LLVM の呼び出し数は次のとおりである。

| 呼び出し | 件数 |
| --- | ---: |
| `kk_alloc` | 0 |
| `kk_object_new` | 263 |
| `kk_object_register_vtable_method` | 415 |
| `kk_object_register_itable_*` | 1196 |
| `kk_vtable_lookup` | 83 |
| `KTypeInfo` 文字列参照 | 0 |

この結果は、少なくともこの polymorphic/abstract override fixture の compiled path では、A の `kk_alloc`/静的 vtable ではなく B の box/registration/lookup 経路が実際に選択されていることを示す。`KTypeInfo` runtime API が存在することだけでは A の codegen 到達性の根拠にならない。

## 比較

### A: KTypeInfo/kk_alloc/静的 vtable を配線する

利点は、nominal type ごとの静的 metadata を持てれば、vtable metadata の理論上の保持量をインスタンス数に比例させずに済むこと、allocation-time のインスタンス辞書登録を減らせることである。

しかし現行コードには、KTypeInfo の fqName、field offsets、vtable/itable、GC descriptor を compiler が生成して runtime allocation に渡す経路がない。実装には少なくとも次が必要になる。

- 全 nominal object の static metadata と function-pointer table の emission、ABI/linkage、初期化順序。
- `kk_object_new` を含む通常 object、array、StringBuilder、collection/primitive/throwable/closure の特殊 box を `kk_alloc` と同じ header/field layout に揃える作業。
- Swift ARC の `passRetained` と tracing GC の `heapObjects`/root scan を一つの所有権モデルにする作業。現状の `objectPointers` と `heapObjects` は別ドメインとして実装されている。
- interface dispatch、dynamic interface slot、reflection/class metadata、外部 C ABI、既存 golden/ABI tests の移行。

測定も A の理想的な lock-free static lookup を示していない。現行 fallback を比較すると、1 object・8 slots・20万回 lookup×5 の中央値は 15,474,541 ns（約 77.4 ns/lookup）だった。これは metadata lock の miss と `heapObjects` lookup、GC lock、KTypeInfo table read を含む未配線 fallback である。したがって、A を採用する根拠としてこの値を「静的 vtable の性能」と解釈してはならない。

### B: 現行 box モデルを正規化して最適化する

利点は、実際の codegen/runtime/ABI テストが既にこの経路を使っていること、移行なしで ARCH-013/016 の前提を固定できること、段階的に辞書を shared immutable dispatch table へ置き換えられることである。

欠点は、現状の `objectVtableMethods`/`objectItableMethods`/`objectInterfaceSlots` が object key を含む metadata dictionary で、registration と lookup の両方が lock を取ること、`RuntimeObjectBox` 系の `passRetained` と `objectPointers` の release が未整理なことである。これは B を棄却する理由ではなく、ARCH-016 と後続の dispatch optimization の入力である。

現行 dictionary hit の同じ測定は中央値 11,140,917 ns（約 55.7 ns/lookup）だった。これは現行経路の比較であり、測定用の function pointer を返すだけの lookup である。実際の indirect call、競合、ARC retain/release は含まないので、絶対性能の契約にはしない。

2,048 objects × 16 methods を `kk_object_new` と `kk_object_register_vtable_method` で作ったとき、metadata entries は正確に 32,768 になった。`getrusage(RUSAGE_SELF).ru_maxrss` は 6,176,768 bytes から 8,880,128 bytes へ増えた（約 2.58 MiB）。これは dictionary 単体ではなく、Swift box、objectPointers、allocator、runtime の増分を含む bounded process RSS である。それでも現行表現の保持量が instances × methods に依存することと、A の type/static-table 表現が types × methods にできる可能性の差は確認できる。

測定 fixture は [`Scripts/benchmark_cases/arch015_object_model.swift`](../Scripts/benchmark_cases/arch015_object_model.swift) であり、次で再実行できる（macOS、ビルド済み Runtime、単一プロセス）。

```text
swiftc -O -I .build/out/Products/Debug -L .build/out/Products/Debug \
  Scripts/benchmark_cases/arch015_object_model.swift \
  -lKotlinRuntime -o /tmp/arch015-object-model
/tmp/arch015-object-model
```

## 採択理由と棄却理由

B を採択する。理由は「現行 master の到達可能性」「既存 ABI/test の所有者」「移行工数と互換性リスク」の三点が同じ方向を示すためである。現行 box hit の測定値も、未配線 fallback より速いという観測を与えている。ただしこれは static KTypeInfo table の将来性能を否定する測定ではない。

A は、静的 metadata による memory scaling の利点がある一方、現行 codegen から到達不能で、ARC/GC ownership と全特殊 box の移行を要求するため、この task の evidence だけで採用するには不十分である。特に `docs/spec.md` J16 と ABI parity tests が KTypeInfo/kk_alloc を直接扱うため、「未使用に見えるから削除する」という判断も棄却する。

## 段階的移行と ARCH-013/016 の前提

1. **ARCH-015（本 PR）**: B を canonical model とし、A の即時削除はしない。`KTypeInfo`/`kk_alloc` の manual ABI/test reachability と current box codegen reachability を decision record に固定する。
2. **ARCH-013 の前提**: primitive fast path は current box model の nominal identity、Any/class/interface dispatch、null/sentinel、ARC registration semantics を壊さないこと。未 box primitive の inline representation を導入しても、primitive 以外の `kk_object_new`/registration 経路を A に混ぜない。`kk_box_int`/`kk_unbox_int` の lock・Set・dynamic cast を削る場合は、tag、非 boxed value、boxed fallback、型誤り、GC/ARC ownership の回帰を個別に測る。
3. **ARCH-016 の前提**: release owner を current `objectPointers` と metadata dictionaries に対して明示すること。`registerRuntimeObject`、`kk_object_new`、特殊 box、KClass cache のそれぞれについて retain/release、metadata cleanup、double release 防止、GC heapObjects との非混同を固定する。完了判定は heap/objectPointers count と bounded RSS の回帰を含める。
4. **ARCH-015 後続**: ARCH-016 の ownership が成立した後、class/type 単位の immutable dispatch table、object から class table への参照、または安全な lock-free read を別 task で比較する。interface の dynamic slot と registration lifecycle を先に定義し、単なる `Any` cast や raw pointer の置換で lock を隠さない。
5. **仕様/ABI gate**: A 側を削除する別 task は、`docs/spec.md` J16、Runtime ABI export parity、手動 KTypeInfo/kk_alloc tests、外部 C callers、generated fixture の所有者が不存在または移行済みであることを確認してから着手する。

## 選ばなかった A 側の dead-code 削除タスク案

**候補タイトル**: `ARCH-015-FOLLOWUP: remove the unconnected KTypeInfo/kk_alloc object model after ABI retirement`

**対象候補**: `KTypeInfo`、`KKObjHeader`、`kk_alloc`、`heapObjects` の mark/sweep-only path、KTypeInfo vtable/itable fallback、対応する未使用 compiler comments/layout metadata、J16 と ABI parity/RuntimeGC fixtures。実際の削除範囲は、削除前の参照・外部 symbol・generated artifact audit で確定する。

**着手条件**:

- compiler LLVM/KIR の全 supported allocation/dispatch path に `kk_alloc`/KTypeInfo の生成がないことを再確認する。
- C ABI consumers、runtime exports、`docs/spec.md` J16、RuntimeTests、ABI parity tests の maintainer ownership と互換性方針を記録する。
- ARCH-016 の ARC release/metadata cleanup と、必要な GC/weak-reference tests の移行が完了している。
- A の手動 tests を current box tests または明示的な compatibility tests に置き換え、削除後も `rg` による残存参照が意図した compatibility shim だけになる。

**完了条件**: dead symbols/branches/tables が削除され、spec/ABI/export inventory/tests/golden が同じ決定に同期し、`swift build`、Runtime focused tests、ABI link validation、関連 diff/golden が green であること。互換性方針が未決定なら削除せず needs attention とする。この候補は本 PR では起票・実装しない。

## 監査境界

編集前に exact `ARCH-015` の current/archived task、open/merged PR、remote branch、git history を検索したが該当 owner はなかった。全 open PR の changed files を確認し、`docs/ARCHITECTURE.md` を変更する open PR は 0 件、`TODO.md` の patch に `ARCH-015` を含む open PR も 0 件だった。Runtime/backend 関連の open PR 自体は存在するため、これらを ARCH-015 の owner と誤認せず、対象 diff に混ぜない。

この PR で変更するのは本 decision record、ARCH-015 の TODO checkbox/link、再現用の bounded measurement fixture だけである。
