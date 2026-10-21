# KLIB 互換性

KLIB 読み込みの検証基準は Kotlin/Native **2.4.21**。同バージョンが生成する
IR ABI は **2.4.0** であり、コンパイラのリリース番号とは区別する。
ABI 2.3.0 から 2.4.0 までを受理し、未実装の将来 ABI は
`KSWIFTK-LIB-0027` で拒否する。`ir_signature_versions` は 1・2 を認識し、
省略時は公式実装と同じく 1 を既定とする。

| 対象 | 実装・検証範囲 |
| --- | --- |
| コンテナ | packed ZIP、unpacked ディレクトリ。`default` または manifest を持つコンポーネントを選択 |
| Manifest | Java properties、継続行、エスケープ、UTF-16 サロゲートペア、重複キー |
| IR テーブル | 固定長・2.4 の可変長サイズ、ファイル別テーブル、宣言 ID 座標。破損 count・size・行境界を検証 |
| IR protobuf | `KotlinIr.proto` の宣言・型・式・文。2.4 以前の式 wrapper と 2.4 の直接 operation、fixed64 の member hash、必須フィールド |
| 文字列 | WobblyTF8。孤立サロゲート、補助文字、内部マーカーと同じ私用文字、NUL を文字列定数として保持 |
| シンボル | 型引数、可変長引数の要素型、公開範囲、modality、同一 KLIB 内のファイル間シグネチャとオーバーロード |
| 関数型 | `kotlin.FunctionN<P..., R>` を関数型として復元。nullable な関数型と、宣言に束縛された型パラメータを保持 |
| 基本実行 | 関数、クラスとプロパティ、コンストラクタ、拡張関数、継承を含む既定引数、先行引数に依存する既定値、空・非空 vararg、仮想呼び出しと明示的 super 呼び出し |
| ラムダ実行 | 非 suspend・0〜6 引数のラムダ。非キャプチャ、複数・入れ子のキャプチャ、`this`、文字列・ジェネリック、共有可変セル、KLIB 内からの `invoke` と例外伝播 |

`KlibManifest.Compatibility.supported` は IR の入力形式に対する判定であり、
全ライブラリの API・実行機能が利用可能であることを意味しない。
現状は IR 宣言から Sema シンボルを構築し、必要な実行本体を KIR に変換する。

完全対応に向けて残る範囲:

- `linkdata` メタデータだけを持つ KLIB・cinterop 宣言の取り込み。最新 main IR が
  意図的に保存しない typealias など、メタデータ由来の API 情報の復元。
- 反射対象を持つ関数参照、プロパティ・クラス参照、ローカル関数・クラスの
  実行本体変換。`richFunctionReference` のうちラムダの invoke 本体は変換するが、
  callable reference の反射メタデータは未対応。
- suspend・context parameter を持つラムダ、7 引数以上、拡張関数型アノテーションの
  receiver 情報、star 投影された関数型の網羅。デコード用モデルと実行機能は別々に検証する。
- メンバー拡張の複数 receiver、context parameter、reified・suspend・inline の
  組み合わせを含む実行 ABI の網羅。既定引数の mask は現在 63 引数分まで。
- vararg spread、try/catch/finally、enum の合成本体など、`KlibBodyLowerer` が
  未対応の警告を出す IR の実行。
- `ir_inlinable_functions` の読み込みと別 KLIB 間の完全なシグネチャ照合、
  外部 Native ABI・ランタイム依存。JS/Wasm の dynamic 操作は各バックエンドの対象と分ける。

回帰 fixture と再生成手順は
[`Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/README.md`](../Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/README.md)。
実物の最新 KLIB の読み込みは `KlibLatestCompatibilityTests`、実行結果は
`KlibLatestBasicsExecutionTests` の O0 / O2 で固定する。
ラムダの回帰は [KUU-2692](https://linear.app/kuu/issue/KUU-2692) と
`KlibLambdaImportTests` / `KlibLambdaExecutionTests` で管理する。
後者は同じ producer をソースと最新 Native KLIB の両方から取り込み、O0 / O2 で比較する。
実行回帰では 0・1・2 引数と上表のキャプチャ・値の種類を確認する。
0〜6 引数の生成には既存の source lambda と共通の callable adapter を使用する。
既存の Kotlin 2.3.10 Native・2.4.20 JS fixture も保持する。

仕様の照合元:

- [公式 Kotlin/Native ライブラリ仕様](https://kotlinlang.org/docs/native-libraries.html)
- [2.4.21 KotlinAbiVersion](https://github.com/JetBrains/kotlin/blob/v2.4.21/compiler/util-klib/src/org/jetbrains/kotlin/library/KotlinAbiVersion.kt)
- [2.4.21 KotlinIr.proto](https://github.com/JetBrains/kotlin/blob/v2.4.21/compiler/ir/serialization.common/src/KotlinIr.proto)
- [2.4.21 IrRichFunctionReference](https://github.com/JetBrains/kotlin/blob/v2.4.21/compiler/ir/ir.tree/gen/org/jetbrains/kotlin/ir/expressions/IrRichFunctionReference.kt)
- [2.4.21 UpgradeCallableReferences](https://github.com/JetBrains/kotlin/blob/v2.4.21/compiler/ir/backend.common/src/org/jetbrains/kotlin/backend/common/lower/UpgradeCallableReferences.kt)
- [2.4.21 lowLevelReaders](https://github.com/JetBrains/kotlin/blob/v2.4.21/compiler/util-klib/src/org/jetbrains/kotlin/library/impl/lowLevelReaders.kt)
- [2.4.21 WobblyTF8](https://github.com/JetBrains/kotlin/blob/v2.4.21/compiler/util-klib/src/org/jetbrains/kotlin/library/encodings/WobblyTF8.kt)
