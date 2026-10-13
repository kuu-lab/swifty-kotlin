# Codegen の内訳計測（KUU-1962）

`-Xfrontend time-phases` は Codegen と Link の LLVM 処理を次の単位で記録する。
計測を無効にした場合は時計を読まない。例外で終わった処理も記録する。

| フェーズ | サブレコード | 内容 |
| --- | --- | --- |
| Codegen | `file facades` / `link info` | AST の file facade と KIR の関数リンク情報 |
| Codegen | `backend init` | LLVM library の探索、trust 検査、dlopen、bindings の context lifecycle 検査 |
| Codegen | `reflection records` | runtime reflection blob に格納する records の構築 |
| Codegen | `emitter setup` | external function の lookup map 等 |
| Codegen | `IR emit` | LLVM context/module、関数本体、reflection globals の構築 |
| Codegen | `IR/reflection globals` | `IR emit` に含まれる reflection blob のシリアライズと globals 構築 |
| Codegen | `target machine` | target machine と data layout の設定 |
| Codegen | `opt pipeline` | module verifier と LLVM new pass manager。O0 は既存の no-op |
| Codegen | `object write` | LLVMTargetMachineEmitToFile。machine code 生成とファイル出力を含む |
| Codegen | `IR print` / `IR write` | LLVM IR の文字列化とファイル出力 |
| Codegen | `inline-KIR artifacts` / `library metadata` | library 用の inline body、完全な metadata.bin の生成・出力 |
| Link | `entry/backend init` | entry wrapper の bindings 取得。通常の driver は Codegen の bindings を再利用 |
| Link | `entry emission` | entry wrapper の context/module 構築と object 出力 |
| Link | `entry/target machine` / `entry/object write` | `entry emission` に含まれる target machine / native emission |
| Link | `Link/swiftc` | 既存の linker subprocess 計測 |

親レコードと子レコードは包含関係にあるため、すべての行を足し合わせない。
`TOTAL` は外側のフェーズのみを合計する。session が保持する library handle の
最終 dlclose はフェーズ配列の破棄時に起こり得るため、性能比較では CLI 全体の
経過時間も測る。Runtime/stdlib の初回構築を warm 結果に混ぜない。

## 削減した処理

従来は runtime reflection にも library 用の完全な `MetadataRecord` を構築していた。
runtime blob は kind、FQName、直接 supertype、arity、5種類の flags、field count、
instance size しか格納しない。`runtimeReflectionOnly` は同じ選択・順序を保ち、
この項目だけを構築する。mangling、型シグネチャ、契約、annotations、dispatch map 等の
構築を省く。records の省略や binary format の変更は行わない。

`.kklib` の metadata.bin は既定の完全な encoder を引き続き使う。
serializer に項目を追加する際は、投影処理も更新し full/projected のバイト一致を確認する。

`makeBackendPhases()` はコンパイル1回ごとの `LLVMBackendSession` を Codegen と Link に渡す。
最初の成功した `loadUsable()` だけを保持し、entry wrapper での再探索・再ロードを省く。
context、module、target machine は各 emitter が個別に所有・破棄する。
通常の driver は呼び出しごとに session を作り、直接の `CodegenPhase()` / `LinkPhase()` は
従来どおり run ごとに新しくロードする。初回の trust 検査、診断、Linux のロックは維持する。

## ローカル比較

2026-10-13、macOS 27 arm64、Apple Swift 6.4 debug build、base `a1ad746b646afab1ccb242033740e0c6528979e0`。
変更前の計測追加版と変更後を交互に各5回実行した。
入力は `fun main() {}`、`--no-stdlib --emit object -Xfrontend time-phases`。
他のビルドが多数動いていたため、各フェーズの wall time は大きく変動した。

| 中央値（ms） | 変更前 | 変更後 |
| --- | ---: | ---: |
| `reflection records` wall time | 492.63 | 147.07 |
| Codegen wall time | 713.67 | 768.53 |
| CLI 全体 wall time | 1779.23 | 1464.61 |
| CLI process CPU time（user + system） | 163.34 | 130.73 |

CPU time は約20%減った。Codegen wall time はこの環境では短縮を確認できず、
hello.kt の TOTAL が15%減るという主張はしない。空の main にも9,435個の
reflection word globals があり、その構築・native emission は今回維持している。

同じ bundled-source hash `38a615de8d71c6b4` の stdlib artifact と準備済み Runtime を使い、
hello.kt の executable も変更前後で交互に各3回比較した。全6回のコンパイルと実行に成功し、
stdout はすべて `hello\n` だった。最初の Runtime 構築はこの表に含めない。

| hello.kt 中央値（ms） | 変更前 | 変更後 |
| --- | ---: | ---: |
| `reflection records` wall time | 1260.01 | 278.69 |
| Codegen wall time | 2875.77 | 1786.76 |
| `entry/backend init` wall time | 5.09 | 0.00 |
| CLI 全体 wall time | 20133.52 | 21986.68 |
| CLI process CPU time（user + system） | 5952.31 | 5686.32 |

この比較では Codegen wall time は約38%、CLI CPU time は約4.5%減った。
CLI 全体 wall time は増えており、TOTAL の短縮は確認できない。
いずれも高負荷環境での観測値であり、issue 記載の約950msと直接比較しない。

比較用の複合 Kotlin 入力（generic/data/sealed/value class、interface、inheritance、
inline/suspend/extension 関数、非公開宣言）では、LLVM IR、library metadata.bin、
library object が変更前後でバイト一致した。共通 stdlib artifact を使った hello.kt の
consumer object も変更前後でバイト一致した。

## 再計測

```bash
swift build
.build/debug/kswiftc Scripts/diff_cases/hello.kt \
  --stdlib-library /absolute/path/to/KSwiftKStdlib.kklib \
  -Xfrontend time-phases -o /tmp/codegen-hello
/tmp/codegen-hello
```

変更前後で同じ bundled-source hash の stdlib artifact を明示的に使う。
最初の1回を warm-up とし、O0/O2、executable/object/LLVM IR/library を区別する。
CLI 全体は subprocess の開始から終了までを測り、負荷が高い場合は process CPU time も記録する。
Python では `resource.getrusage(resource.RUSAGE_CHILDREN)` の user/system 差分を使える。

対象テストは `CodegenPhaseTimingTests`、`RuntimeReflectionMetadataEmitterTests`、`PhaseTimerTests`。
投影の比較は公開/非公開、enum/object/annotation/overload と、新規生成した generic `.kklib`
の import を含む。計測有無による IR/object 一致、O0/O2、bindings 再利用と context 分離も確認する。

最終検証は対象製品のビルドと上記3スイートがすべて exit 0。
`PhaseTimerTests` は11件、serializer は22件、`CodegenPhaseTimingTests` は4メソッド・10条件が成功した。
全体テスト、Golden、全件 kotlinc diff は未実行。
