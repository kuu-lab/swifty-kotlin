# Codegen 実行テスト fixture

`CodegenBackendFixtureTests`（[`../Codegen/CodegenBackendFixtureTests.swift`](../Codegen/CodegenBackendFixtureTests.swift)）が
このディレクトリを実行時に走査し、各 fixture を `kswiftc` でコンパイル・実行して
stdout を比較する。`Scripts/diff_cases` と同じく「ファイルを置くだけ」で自動検出される。

## fixture の形式

1 fixture = 1 ディレクトリ。以下の 2 ファイルを含める:

- `*.kt` … コンパイル・実行する Kotlin ソース（`fun main()` を持つ実行可能プログラム）。1 ディレクトリにつき 1 つ。
- `expected.txt` … 実行後に期待する stdout（`\r\n` は `\n` に正規化して比較）。

ディレクトリは領域単位でネストしてよい（例: `collections/list_sum/`）。
ハーネスは `expected.txt` を持つ全ディレクトリを再帰的に fixture として検出する。

## 新しいケースの追加

```
Fixtures/<領域>/<ケース名>/
  <ケース名>.kt      # fun main() を持つ実行可能ソース
  expected.txt       # 期待 stdout
```

新規テストクラスやボイラープレートは不要。ファイルを追加してテストを再実行するだけでよい。
