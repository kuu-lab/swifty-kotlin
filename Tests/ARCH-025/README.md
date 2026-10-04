# ARCH-025 Kotlin compiler testData subset

ARCH-025 は、JetBrains Kotlin compiler の `compiler/testData` から、Kotlin 2.3.10 に対応する小さな適合サブセットを輸入し、ローカルで受理／拒否と `box(): String` の実行契約を追跡するための専用台帳です。既存の Golden、`Scripts/diff_cases`、CI、ARCH-023 の fuzzer、ARCH-024 の診断 differential harness には接続しません。

## 固定点と帰属

- upstream: `https://github.com/JetBrains/kotlin.git`
- ref: `v2.3.10`
- immutable revision: `679366a83f99851b42f64795f10ed803ff011c73`
- license: Apache License 2.0
- imported files: `fixtures/` 以下。各 upstream path と SHA-256 は `manifest.tsv` に固定しています。

輸入元の大きな tree、生成された `.class`／`.fir`／期待値ファイルは vendor しません。輸入した Kotlin source は upstream のバイト列を保持し、実行時だけ runner が一時入力を作ります。ライセンス帰属はリポジトリの [`NOTICE`](../../NOTICE) に記載しています。

## 選定範囲と初回網羅率

固定 revision の source 件数を、diagnostics は `compiler/testData/diagnostics/tests` の `.fir.kt` を除く `.kt`、codegen は `compiler/testData/codegen/box` の `.kt` として数えました。

| scope | upstream source count | selected records | initial coverage |
| --- | ---: | ---: | ---: |
| diagnostics | 7,787 | 3 | 0.039% |
| codegen/box | 10,009 | 4 | 0.040% |
| combined | 17,796 | 7 | 0.039% |

この値は upstream 全体の完成度を表すものではなく、「仕様基準の選定レコードをどこまで台帳へ登録したか」の初回スナップショットです。`unsupported` の 1 件も silent omission を避けるため分母に含め、実行済み supported record は 6 件です。

選定基準は、単一ファイル、Kotlin 2.3.10 の testData に存在、platform-specific な補助ファイルなし、かつ既存コンパイラの修正を要求しない小さな契約であることです。diagnostics は `Basic`、`LValueAssignment`、`Nullability` を frontend の受理／拒否境界として採用しました。codegen は `simpleBox`、`defaultargs`、`simpleStringPlus` を `box(): String == "OK"` の代表として採用しました。

`for_loops_empty_range.kt` は代表的な codegen source ですが、upstream の `WITH_STDLIB` と `kotlin.test`／JVM helper 前提を持つため、初回から推測で代替せず `unsupported` として登録しています。これは ARCH-025 の未対応台帳であり、コンパイラ修正の起票や実装ではありません。

## 実行方法

```bash
# Resolve the pinned upstream revision without changing the worktree.
bash Scripts/import_arch025_testdata.sh --dry-run

# Import missing files; existing matching files are left untouched.
bash Scripts/import_arch025_testdata.sh

# Verify revision, source hashes, and checked-in fixtures.
bash Scripts/import_arch025_testdata.sh --verify

# Run serially against the local debug compiler and print the ledger.
bash Scripts/run_arch025_testdata.sh

# Regenerate the deterministic checked-in ledger.
bash Scripts/run_arch025_testdata.sh --write-ledger
```

`run_arch025_testdata.sh` は `kswiftc` だけを呼び、`diagnostics` の `<!...!>` marker 除去と codegen の `fun main() { print(box()) }` 追加を temporary directory 内で行います。診断コードやエラー行集合は ARCH-024 の責務のため比較しません。worker は常に 1 個で、既存 G にも含めません。

台帳の `status` は `pass`、`fail`、`unsupported` の 3 値です。`pass` は manifest の受理／拒否または box 出力契約を満たしたもの、`fail` は契約不一致または hash 不一致、`unsupported` は manifest で明示した未対応条件です。

## 更新手順

1. Kotlin 2.3.10 に対応する upstream revision を確認し、`import_arch025_testdata.sh` の immutable revision と ref を同時に更新する。
2. upstream path を manifest に追加し、byte-preserving SHA-256、期待契約、`supported`／`unsupported`、選定根拠を記録する。生成物や巨大なディレクトリは追加しない。
3. `--dry-run` で取得予定を確認し、通常実行で不足 fixture だけを輸入する。既存 hash が異なる場合、importer は上書きせず停止する。
4. `--verify`、runner、`--write-ledger` を実行し、ledger diff が選定変更だけであることを確認する。
5. 変更は ARCH-025 専用 PR に限定し、CI／既存 G へ接続する場合は別 TODO とする。
