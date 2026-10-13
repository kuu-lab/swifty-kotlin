# kotlin.test 追加 assertion (KUU-1703〜1714)

基本 assertion の PR #8272 を前提に、例外、型、包含、配列の内容、浮動小数点許容誤差を実装する。

## 上流契約

JetBrains/kotlin revision `150f34458460c5d688ba80e13f269ca6715f32b4` の
`libraries/kotlin.test/common/src/main/kotlin/Assertions.kt`、`Utils.kt`、
`AssertContentEqualsImpl.kt` を使用する。安定版 API は Kotlin 2.3.10 と照合し、
実験的 lazy-message overload は上流の `@SinceKotlin("2.4")` と
`@ExperimentalKotlinTestApi` を保持する。
`checkResultIsFailure(KClass, ...)` は 2.3.10 Native 実装に従う。

| 子チケット | API |
|---|---|
| 1703 / 1707 | assertFails、assertFailsWith (reified / KClass) |
| 1704 / 1705 | assertIs、assertIsNot |
| 1706 | assertContains: Iterable / Sequence / Array |
| 1708 | assertContains: 6 signed primitive / 4 unsigned 配列 |
| 1709 | assertContains: Int / Long / Char / UInt / ULong / ClosedRange / OpenEndRange |
| 1710 | assertContains: Map / CharSequence (char、substring、regex) |
| 1711 / 1712 | assertContentEquals: Array と12 primitive/unsigned 配列、共通 helper |
| 1713 / 1714 | Float / Double の absoluteTolerance equals / notEquals |

`assertIs` は返値と smart cast 契約を持つ。チケット1705の記述に反して
上流 `assertIsNot` に契約は存在しないため、負の型契約は追加しない。
`assertContentEquals` の generic public signature は上流通り `Array<T>?`。
浮動小数点配列の contains は上流に存在しないため追加しない。
Iterable/Sequence/Set の content overload は、この12子チケットの対象外。

例外ブロックは `() -> Any?` を受け付け、HIDDEN な `() -> Unit` overload は
binary compatibility として残す。例外の同一性、親型での捕捉、失敗時の cause、
正常終了したブロックの結果、非ローカル return を検証する。
KClass/KType の表示は JVM と Native で異なるため、型 assertion のメッセージと
assertFailsWith の型名は、共通の意味を示す prefix/結果/cause を比較する。
assertFails と内容・許容誤差の安定メッセージは stdout 全体を比較する。

## 必要だった compiler 修正

- `IntArray?::contentToString` のような generic 引数を持たない nullable 型参照の解析。
- explicit receiver から generic extension callable reference の型を推論。
  具体的 expected type がある場合は receiver と expected type を同時に解き、
  covariant receiver の型を早期に固定しない。nullable receiver を保持する。
- star receiver と out projection の型制約分解。
- lexical な extension function value の package extension より高い優先順位。
  receiver の実 member は引き続き優先する。
- `returns(false) implies (a != null && b != null)` の両 conjunct を記録。
  OR の各 operand は独立した保証として採用しない。
- top-level の明示的契約を、呼出側の body より先に収集する。
  callsInPlace と implication metadata の登録を重複除去する。
- 配列の公開 `get` を source declaration として定義し、callable reference に対応。
  body の index 操作は既存 intrinsic に従う。
- unsigned 配列 contains の source-backed loop を追加。
- imported inline 本体で reified token の raw word 型と callback parameter の
  local symbol identity を保持する。nested callback の返値を外側 message callback
  の返値から推測しない。
- 複数 capture を持つ closure の inline 展開では、既存 callback ABI の
  単一 environment に capture を詰める。
- FloatingPointRange の callable reference は runtime range probe を使用し、
  ユーザー定義の実装は既存 interface dispatch に渡す。
  整数 range の OpenEndRange 登録も ClosedRange と揃える。
- 型情報がない imported inline 本体でも、resolved accessor から
  Throwable.message の raw String? ABI を識別する。
- Sequence.indexOf は iterator で一致までを消費し、assertContains の検索で
  toList() による全要素の先行消費を避ける。

## 対象検証

`Scripts/diff_cases/kotlin_test_{types,failures,contains,content,tolerance,callable_helpers}.kt`
と `.expected` は実際の Kotlin/JVM 2.3.10 + 同版 kotlin-test.jar で採取する。
包含24 overload、配列内容13 overload、許容誤差4 overload と関連 compiler 回帰を含む。
Sequence は成功要素までの消費回数、内容は null/size/element、NaN/符号付きゼロ、
許容誤差は境界/NaN/infinity/負値と NaN tolerance の上流診断を観測する。

`kotlin_test_families_lazy.kt` は candidate-only marker を持つ。
2.3.10 の JVM jar は2.4の APIを提供しないため、stable oracleとして使用しない。
全 lazy overload の成功/失敗と message callback 呼出回数、content null/size を検証する。

```bash
swift build
swift test --filter 'CallableReferenceParsingTests|AssertionHelperRegressionTests|LibraryInlineImportLabelTests|InlineErasedLambdaABITests|InlineNestedCaptureTests|testFloatingPointRangeReferencesProbeBeforeInterfaceDispatch|testKotlinTestAssertionFamilies|CodegenBackendSequenceIndexOfTests'
```

Backend は対象 fixture を同じ executable へ batch し、source injection と既存 artifact
の両方を実行する。artifact 分岐は `.kklib/manifest.json` の存在を必須とし、
source fallback による偽の通過を防止する。

全 Swift テスト、全 Golden、全 diff、macOS の実行はこの対象検証には含まない。
