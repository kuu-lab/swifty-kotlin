# KUU-1604: Kotlin/JS 2.3.10 の監査 fixture

契約と7実装チケットの所有範囲は
[`../../js-annotations-contract-2.3.10.md`](../../js-annotations-contract-2.3.10.md) を参照。
このディレクトリは reference の証拠を保存する。
candidate-only runner の製品実装・CI 接続は KUU-1612 以降の担当である。

| ファイル | 役割 |
|---|---|
| `valid/*.kt` | warning なしで受理され、Node で動作する7つの Kotlin/JS fixture |
| `valid/*.mjs` | export/static の肯定観測と、marker が export しない否定観測 |
| `diagnostics/*.kt` | 原形の snapshot、分離した無効入力、warning のみで受理される入力 |
| `expectations.json` | 固定した source/consumer hash、診断、stdout/stderr/終了コード、native 契約、provenance |
| `evidence/reference-results.json` | Kotlin/JS の実コンパイル/実行記録。native PASS を意味しない |
| `evidence/sources.json` | v2.3.10 commit 固定の根拠リンクと raw source SHA-256 |
| `evidence/native_observations.export.d.mts` | 統合 fixture から生成した TypeScript 宣言の保存例 |
| `capture_reference.py` | 監査用の再採取/期待値比較。KSwiftK や JVM compile/run reference を実行しない |

## Toolchain

- Kotlin compiler / `kotlin-stdlib-js.klib`: **2.3.10**、公式配布 archive を checksum 照合して使用。
- upstream commit: `679366a83f99851b42f64795f10ed803ff011c73` (`v2.3.10`)。
- archive SHA-256: `c8d546f9ff433b529fb0ad43feceb39831040cae2ca8d17e7df46364368c9a9e`。
- 採取環境: macOS arm64、OpenJDK 27 (Homebrew)、Node **v26.10.0**、Python 3。
- Kotlin/JS は ES2015 / ES modules、統合/file-name fixture は per-file。
- `kotlinc -version` は toolchain 記録だけに使う。JVM 用の Kotlin 入力コンパイルや jar 実行は行わない。

既定 Homebrew Kotlin は採取時点で 2.4.20 だったため使用していない。
version 表示だけでなく、compiler jar / JS stdlib klib / JS source jar の hash も照合する。
Swift revision と host/toolchain の実際の出力は evidence 内に保存されている。

## 再採取

リポジトリルートで実行する。出力先は新しい空ディレクトリでなければ失敗する。
archive の準備から再現する macOS の例:

```bash
audit_root=$(mktemp -d /private/tmp/kuu1604-reference.XXXXXX)
curl --fail --location --output "$audit_root/compiler.zip" \
  https://github.com/JetBrains/kotlin/releases/download/v2.3.10/kotlin-compiler-2.3.10.zip
/opt/homebrew/bin/bash Scripts/verify_kotlin_compiler_archive.sh \
  "$audit_root/compiler.zip" \
  c8d546f9ff433b529fb0ad43feceb39831040cae2ca8d17e7df46364368c9a9e \
  "$audit_root/toolchain" 2.3.10
python3 docs/fixtures/js_annotations/capture_reference.py \
  --kotlin-dir "$audit_root/toolchain/kotlinc" \
  --output-dir "$audit_root/capture"
```

checksum 照合済み toolchain を再利用する場合は最後の Python コマンドだけでよい。
対象を限定する場合は `--case native_observations` などを指定する。
既存の保存記録と現在の fixture/期待値の整合性だけを確認するコマンド:

```bash
python3 docs/fixtures/js_annotations/capture_reference.py \
  --check-record docs/fixtures/js_annotations/evidence/reference-results.json
```

capture は `-Xir-produce-klib-file` の source → klib と、
`-Xir-produce-js -Xinclude=...` の klib → JS を分ける。
全体の呼出しは case ごとに evidence の配列 `command` に保存されている。
`<KOTLIN_DIR>` は展開済み kotlinc directory、`<CAPTURE_DIR>` は監査の出力先へ置換する。
generated JS の依存モジュールも必要なので、consumer を単独の export file だけで移動しない。

## 期待値と観測

`expectations.json` の `schemaVersion` は1。
`cases` は `id`, `source`, `sourceSha256`, `lanes`, `reference`, `nativeContract`, `provenance`
を持つ。`reference.compile` は終了コード、stdout、severity/name の診断 multiset。
有効 fixture は `werror: true`、診断 fixture は既定の warning severity で採取する。
`reference.link` は終了コード、追加 flags、必須の相対 artifact 名。
`reference.run` / `consumer` は stdout/stderr と終了コードの完全一致。
consumer の script hash と module 相対パスも固定する。

`nativeContract.compile.diagnostics[].kind` は upstream ID を用いた**意味分類**。
KSwiftK 側の番号コードをこの文字列だと仮定しない。後続 runner は診断 adapter に
根拠のある対応表を持ち、未対応 code を失敗にする。
`nativeContract.status` は `required-by-followup-not-yet-implemented`。
source injection / `.kklib` × O0/O2 の実行で満たされるべき契約であり、採取済みの結果ではない。
`original` は複合無効入力の audit-only、`js_dynamic_views` は JS 専用で native から除外する。
consumer も `js-emission-reference` lane であり、native の通常 call の PASS に混ぜない。

元ケースの message / 2:3:4 / value=7 は `native_observations` で全て観測する。
JS の native object count は `js_dynamic_views` が size/size/length で別に観測する。
readonly array の typed `size` と typed `length` は両方とも無効。
6 conversion の read-only/mutable 戻り値はコピーで、view は共有 backing を保持する。
`typed_views` は古い snapshot の値と、同じ view の新しい内容を併記する。

compile 60秒、JS link 120秒、run/consumer 10秒を上限とする。
timeout、signal/非ゼロ終了、診断/出力不一致、期待値/必須 artifact/hash の不足は失敗にする。
raw compiler stderr（進捗/時間情報を含み得る）と runtime stderr は別の field。
runtime の文字列は UTF-8 をそのまま保持し、trim や newline の自動正規化を行わない。
capture は結果を保存して比較し、期待値を自動更新しない。
`--check-record` は過去の記録の整合性確認であり、現在の compiler の再実行ではない。

## 今回の検証範囲

23 Kotlin fixture の compile/診断、7 fixture の JS link/run、2つの JS consumer を採取。
JS で生成される file 名・export・static call と、native 互換へ渡す Kotlin の観測を分離した。
元 `Scripts/diff_cases/js_annotations.kt` と SKIP-DIFF は保持。
製品 source、Runtime/ABI、candidate runner、CI は変更していない。
`swift build` は成功（44.41秒）。全 Swift テスト/全 Golden/全 diff、
KSwiftK source injection / `.kklib` / O0/O2 は未実行。
