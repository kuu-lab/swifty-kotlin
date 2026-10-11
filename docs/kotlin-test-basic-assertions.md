# kotlin.test 基本 assertion (KUU-1694〜KUU-1702)

`assertTrue`、`assertFalse`、generic `assertEquals` / `assertNotEquals`、
`assertSame` / `assertNotSame`、`assertNull` / `assertNotNull`、`fail`、
`expect`、`todo` を bundled Kotlin source として追加する。
実際の判定と例外生成には既存の `Asserter` / `DefaultAsserter` を使う。

stable API の基準は Kotlin 2.3.10。source の由来は JetBrains/kotlin
revision `150f34458460c5d688ba80e13f269ca6715f32b4` の
`libraries/kotlin.test/common/src/main/kotlin/kotlin/test/Assertions.kt`。
同 revision の実験的 lazy-message overload は `@SinceKotlin("2.4")` と
`@ExperimentalKotlinTestApi` を保持する。2.3.10 の JVM oracle にこの
overload が存在するとは扱わない。

stable な8 fixture の期待出力は実際の Kotlin/JVM 2.3.10 + kotlin-test.jar
と比較する。`todo` は Kotlin/Native 2.3.10 の
`kotlin-native/runtime/src/main/kotlin/kotlin/test/Assertions.kt` に従い、
block を実行せず `TODO` を出力する。JVM は呼び出し位置を加えるため、
この fixture と 2.4 lazy-message fixture は理由付きの candidate-only とする。

## 検証

```bash
swift build
bash Scripts/swift_test.sh --no-parallel --filter \
  'BundledStdlibExecutionTests/testKotlinTestBasicAssertions|NegatedBooleanContractTests|MetadataSerializerTests/testContractImplicationsRoundTrip|BuildKIRRegressionTests/functionTypedDefaultValueIsMaterializedInDefaultStub'
bash Scripts/test_swift_test_failure_parser.sh
```

各 stable fixture は `Scripts/diff_cases/kotlin_test_{true,false,equals,not_equals,identity,null,fail,expect}.kt`
と同名 `.expected`。関連ケースを別 package へ分離して一度にコンパイルする
execution matrix は、source injection と新しい `.kklib` の両方で実行する。
artifact lane は manifest が存在することを必須にし、source fallback による
誤った成功を防ぐ。

成功/失敗、null/空/custom message、値と参照の比較、cause の同一性、
`Nothing` の Elvis 式、lazy message の評価回数、block の単一実行、
`callsInPlace(EXACTLY_ONCE)` の definite assignment、contract による
smart cast、block 内での Asserter 切り替えを確認する。

`returns() implies (!actual)` は false の引数条件を metadata に記録する。
inline 関数の既定引数を使う際も default stub を inline 展開し、ラムダの
捕捉値を保持する。新しい library は non-reified の inline default stub も
保存/復元し、古い library の native stub は引き続き利用できる。

対象の filtered tests と fixture だけを確認する。全 Swift テスト、全 Golden、
全 diff、macOS 実行はこの変更のローカル検証範囲に含めない。
