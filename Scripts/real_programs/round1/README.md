# 公開 Kotlin consumer 回帰コーパス 第1弾

[KUU-1854](https://linear.app/kuu/issue/KUU-1854) の元の23本を保存する。
元の実装を変更せず、当初の検証で追加した `Main.kt` を別ファイルで渡す。
QuickSort の BubbleSort 依存も含め、上流ファイルは計24個。

| 上流 | 固定コミット | ケース数 |
|---|---|---:|
| [TheAlgorithms/Kotlin](https://github.com/TheAlgorithms/Kotlin/tree/b913c1d85c972fd1e679c5d832d6458b21be8fb0) | `b913c1d85c972fd1e679c5d832d6458b21be8fb0` | 11 |
| [DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns](https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/tree/1f89f062a056e24cc289ffdd0c6e23cadf8df887) | `1f89f062a056e24cc289ffdd0c6e23cadf8df887` | 12 |

`manifest.json` は、上流URL、revision、ソース・Main・license・期待出力の
SHA-256、期待終了コード、関連子課題を保持する。各ケースに上流のMIT licenseを同梱する。
上流ソースとlicenseは、固定コミットのGitオブジェクトとのバイト一致を確認した。

## 期待出力の由来

2026-10-12 JST の元の検証資料 `kotlin-compatibility-evidence.zip` から復元した。
アーカイブのSHA-256は
`7a9ca795b500661f679dc9377dccf1200a2926d1acdb9e4091236ba029c76d5f`。
`Main.kt` も同アーカイブとバイト一致する。

`expected.stdout` / `expected.stderr` は Kotlin **2.3.10** / OpenJDK **27** で
23本すべてがcompile/run exit 0になった実測結果。すべての期待stderrは空。
期待出力をnativeの実測値で更新してはならない。

当初のcompiler `3c196cd3f42fc4167df66e585d50ba6ae6108263` では、O0で17本一致、
5本compile失敗、1本誤計算。不一致6本のみO2で再現済みだった。
これは過去の記録であり、統合後のO0/O2全23本の成功を示すものではない。

## 2026-10-13 JST の再検証

compiler commit `3858ce74e43330e31d416daa921eb0095896f878`、Kotlin 2.3.10 / OpenJDK 27、
同じfresh stdlib `.kklib` で全69実行を確認した。

| レーン | 出力・終了コード一致 | compile失敗 | 誤計算 |
|---|---:|---:|---:|
| JVM | 23 | 0 | 0 |
| native O0 | 17 | 5 | 1 |
| native O2 | 17 | 5 | 1 |

以前未確認だった正常17本のO2も一致した。5本のcompile失敗と
MatrixChainOrderの `26000` → `24000` はO0/O2共通で、既存6子課題に対応する。
環境エラー・タイムアウト・中断は0。ランナーの10テストと `swift build` は成功。
全Swift tests、既存diffケース全体、全23本のsource stdlib経路は未実行。

KUU-1854は子修正の統合後に再検証が必要で、`complete_verification=false`。
このスナップショットはCI結果や修正完了の根拠としては扱わない。

## 実行

まず `swift build` で対象compilerをビルドする。ランナーはSwiftビルドを行わない。
既定では `.build/debug/kswiftc`、native build systemでは
`.build/out/Products/Debug/kswiftc` も探索する。別のcompilerは `--kswiftc` で指定する。

```bash
python3 Scripts/real_programs/run.py --validate-only

# KOTLINC must point to the Kotlin 2.3.10 launcher.
# JAVA_HOME and JAVA_BIN should select the same installed JDK.
JAVA_HOME=/path/to/jdk27 \
KOTLINC=/path/to/kotlin-2.3.10/bin/kotlinc \
JAVA_BIN=/path/to/jdk27/bin/java \
python3 Scripts/real_programs/run.py --lane all --output-dir /tmp/kuu-1854-run
```

`--lane all` はJVM参照とnative O0/O2の計69実行を行う。
native側はそのcompilerで**新規生成した1個のstdlib `.kklib`**を共有する。
出力ディレクトリは未使用のパスを指定する。省略時は `.artifacts/real_programs/` に
新しいディレクトリを作る。

JVMのバージョンが2.3.10と異なる場合、ソース等のハッシュが異なる場合、
既存の出力ディレクトリを指定した場合は、成功判定を行わず終了する。
compile/link失敗、タイムアウト、run終了コード、stdout/stderrの差分をすべて検出する。
出力の正規化や例外ログの削除は行わない。

各実行のコマンド・終了コード・所要時間は `result.json`、両出力は
`compile.{stdout,stderr}` / `run.{stdout,stderr}` に残る。
`report.json` は全結果、compilerのSHA-256、checkout revisionとSourcesの変更状態、
共有stdlibの全ファイルのSHA-256、対象ケースとレーンを記録する。
終了コードは全対象成功なら0、不一致なら1、環境・コーパス不備なら2。

`complete_verification` がtrueになるのは `--lane all --stdlib-mode library` で
全23本が成功した場合のみ。`--case` の部分実行、`--lane native` のみの成功、
source stdlibのみの検証を共有artifact経路を含む全体完了として扱わない。
既知の失敗をskipする仕組みはない。

```bash
# Reproduce the original MatrixChainOrder consumer in both optimization modes.
python3 Scripts/real_programs/run.py --lane native --case matrix_chain

# Exercise source injection instead of the shared artifact.
python3 Scripts/real_programs/run.py --lane native --stdlib-mode source --case matrix_chain

# Check runner failure detection without building or running the compiler.
python3 -m unittest discover -s Scripts/real_programs/tests -v
```

デフォルトのcompile timeoutは600秒、stdlib buildは1200秒、runは10秒。
必要なら `--compile-timeout` / `--stdlib-timeout` / `--run-timeout` で指定する。
全Swift tests、既存diffケース全体の代わりにはならない。

初回リンクではcompilerがRuntimeをSwiftPMでビルドすることがある。
`sandbox_apply: Operation not permitted` で止まった場合は実行環境の制限として記録し、
通常の承認されたビルド権限でRuntimeを準備してから再実行する。
その状態で正常consumerまでcompile失敗した結果を、互換性の回帰として数えない。
Runtime準備の成功は、通常のリンク経路で作成されるcompleted manifestで確認する。

## 既存の修正課題との対応

| 元consumer | 子課題 | 元の症状 |
|---|---|---|
| `matrix_chain` | [KUU-1855](https://linear.app/kuu/issue/KUU-1855) | `26000` が `24000` になる |
| `matrix` | [KUU-1856](https://linear.app/kuu/issue/KUU-1856) | `java.lang.IllegalArgumentException` import |
| `stack` | [KUU-1856](https://linear.app/kuu/issue/KUU-1856), [KUU-1857](https://linear.app/kuu/issue/KUU-1857) | 例外型、`java.util.ArrayList` import |
| `queue` | [KUU-1858](https://linear.app/kuu/issue/KUU-1858) | `java.util.LinkedList` API |
| `graph` | [KUU-1858](https://linear.app/kuu/issue/KUU-1858), [KUU-1860](https://linear.app/kuu/issue/KUU-1860) | `LinkedList`、`putIfAbsent` |
| `median` | [KUU-1859](https://linear.app/kuu/issue/KUU-1859) | `java.util.Arrays.sort` static import |

子課題の修正はそれぞれのtask・branch・PRで扱う。親の完了条件は、修正統合後の同じ
compilerとfresh stdlibで、この23本のJVM/O0/O2比較がすべて成功すること。
