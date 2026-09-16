# ARCH-002: LLVM 中間最適化パイプラインの決定記録

## 決定

LLVM の new PassManager C API を `LLVMCAPIBindings` から動的ロードし、
`NativeEmitter` が object/LLVM IR の emit 前に `default<O1>`、`default<O2>`、
`default<O3>` を実行する。`-O0` は従来どおり最適化を行わず、デバッグ用の
スタックスロットと DWARF の挙動を維持する。

最適化を実行する場合は、選択した target machine の target triple と data layout
を module に先に適用する。pipeline の入口では `LLVMVerifyModule` を
`LLVMReturnStatusAction` で呼び、壊れた IR は LLVM の abort ではなく
`LLVMBackendError` として報告する。`LLVMErrorRef` は
`LLVMGetErrorMessage` / `LLVMDisposeErrorMessage` で、検証メッセージは
`LLVMDisposeMessage` で解放する。

## stdlib artifact の可視性

`stdlibOnly` の object は、consumer が metadata から参照する entry point を
O2 の global DCE が削除しないよう、stdlib artifact 内では `external` のままに
する。通常の source-backed bundled stdlib は従来どおり `linkonce_odr` で重複を
排除する。

## 回帰対象

最初の O2 実行で検出された malformed IR は、次の回帰テストで固定する。

- coroutine state machine の resume continuation 選択
- enum constructor の source `Enum(name, ordinal)` super delegation
- nested constructor の二重 emit
- vararg constructor の packed `List<T>` ABI
- virtual getter/method の同名 arity cache collision
- imported function pointer の throwing channel 誤指定

## 検証記録（2026-09-16）

- `swift build`: PASS（既存の warning のみ）。
- `bash Scripts/swift_test.sh --no-parallel --filter 'LLVMOptimizationPipelineTests|LLVMOptimizationRegressionTests'`:
  2 suites / 10 tests PASS。
- `bash Scripts/diff_kotlinc.sh --stdlib-library /tmp/kuu497-stdlib.kklib --no-parallel Scripts/diff_cases/llvm_optimization_pipeline.kt`:
  O0 focused は `total=1 failed=0 passed=1 skipped=0`。
- O2 focused は同ケースを `kswiftc -O2 --no-stdlib --stdlib-library` で実行し、
  kotlinc と同じ 5 行（`0`, `-5`, `5`, `-2147483648`, `negative`）を確認。
- PR #6684 の CI run `34711470516` は debug/release build、全 Swift 検証、
  repository checks、kotlinc diff 4 shard が PASS。diff shard の Summary は
  `338/338/338/340 passed`, `failed=0`（skip は `19/19/19/16`）。

## 性能測定

macOS arm64、debug `kswiftc`、同一の prebuilt stdlib artifact、
`Scripts/benchmark_cases/for_in_range.kt`（100 万回ループ）、各 5 回の中央値。

| 構成 | 中央値 |
| --- | ---: |
| O0（pipeline 無効） | 606.739 ms |
| O2（`default<O2>`） | 611.425 ms |

この probe では runtime/boxing が支配的で、O2 の差は +0.8%（測定誤差範囲）
だった。最適化の成立条件は runtime 時間の単純な短縮ではなく、IR probe の
temporary stack slot 消去（`LLVMOptimizationPipelineTests`）とする。

O2 の全 diff を常設する CI lane は ARCH-003（KUU-498）の責務であり、本記録の
focused O2 検証とは分離する。
