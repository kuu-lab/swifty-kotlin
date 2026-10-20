# JVM stdlib のソース化

既存のJVM対応機能は、このリポジトリから生成した `kswiftk-stdlib.jar` を使って実行する。
対応済みのSequence・Regex・unsigned・coroutine・reflection・lazyにも、公式
`kotlin-stdlib.jar`／`kotlin-reflect.jar` の実行時指定は不要。
これは公式stdlibの全公開APIや、任意の外部Kotlinライブラリへの互換性を意味しない。

## ソースと境界

- `Sources/CompilerCore/Stdlib/jvm/manifest.json` が共有KotlinソースとABI宣言を選択する。
- `Stdlib/jvm/declarations/` はフロントエンドの型検査用契約。仮のbodyをJARの実装として出力しない。
- `Stdlib/jvm/kotlin/` の `.kt` とmanifestの `commonSources` を通常のJVMパイプラインでコンパイルする。
- `excludeFromStdlibBuild` で宣言契約と実装ソースを分離し、同じABIを二重生成しない。
- `runtimeClassAliases` はunsignedの実装クラスを公開名 `kotlin/UInt` などへ対応させる。適用はstdlib生成時だけ。
- `platform-operations.json` はJDK constructor／method／fieldへの接続を記述する。分岐・反復・既定値・例外処理はKotlinソースへ置く。
- monitor命令、Resultの符号化された値、suspendCoroutineなど、JVM命令やcoroutine変換に必要な少数の操作はコンパイラがlowerする。
- JVM用ソースと契約はNativeのbundled stdlibへ混入させない。

Unit、Function、Pairは共有ソースを使用する。Function0〜22、Metadata、DefaultConstructorMarker、
Intrinsics、InlineMarker、lateinit例外、SpreadBuilderとprimitive spread builderもソースから生成する。
組み込み型の `.kotlin_builtins` とpackage-part indexは独自生成し、公式JARのclass／resourceをコピーしない。
アプリケーション側の小さな互換クラスは、独自JARが明示classpathにある場合には重複出力しない。

## 実装範囲

| 範囲 | Kotlinソースの実装 |
|---|---|
| 基礎 | print／println、Pair／to、Unit、関数型interface、null検査、inline marker |
| 事前条件 | inline check、error、IllegalStateExceptionのmessageと遅延評価、checkのsmartcast契約とKotlin metadataへのexport、Nothing経路のKotlinNothingValueException |
| 文字列 | UTF-16、検索・置換・split・trim／indent／margin、大小文字・数値変換、StringBuilderと高階操作 |
| collection | List／Set／Map factoryと変換、groupBy／associate／partition／zip、joinToString、sortedBy／windowed／chunked、配列overload |
| Sequence | factory、generateSequence、遅延map／filter／flatMap、zip／window／distinct、終端、一回消費制約 |
| Sequence builder | SequenceScope、yield／yieldAll、単独値と委譲iteratorの状態機械、再開・終了・失敗 |
| Regex | JDK Pattern／Matcher、option・group・range、置換・split、遅延findAll／splitToSequence |
| unsigned | UInt／ULong／UByte／UShortと配列のvalue-class ABI、box/unbox、比較・表示、飽和変換と浮動小数点丸め |
| lazy／委譲 | monitorによるSYNCHRONIZED、CASによるPUBLICATION、NONE、指定lock、再試行・null保持、Delegatesとproperty token |
| coroutine | Result／Failure、Continuation、EmptyCoroutineContext、SafeContinuation、trampoline、startCoroutine、suspend main待機、公式Kotlinのsuspend lambda補助ABI |
| reflection | KClass／KCallable／KProperty、member・constructor・parameter・annotation、bound/unbound参照、call／callBy／callSuspend、value-class戻り値 |

Sequenceはiteratorごとに状態を持ち、windowのskipを次の要求まで遅延させる。
yieldAllは委譲iteratorを一度に展開せず、失敗・finallyの評価順も保持する。
reflectionはJava reflectionとKotlin metadataの双方を使い、flags、JVM signature、型、既定引数を復元する。
同じ引数数のoverloadでも完全なdescriptorでdefault dispatcherを選択し、継承memberの重複を除き、parameterのcallable所有者を保持する。
空collectionとRegexのgroup一覧はJDKのCollection ABIとKotlinのreadonly markerを保持する。
可変collectionの型判定・castはnullableとreadonlyの違いを維持し、escaping reified closure・参照・匿名objectにも伝播する。
repeatable annotationは実際のJava Repeatable containerだけを展開する。

## 生成と確認

```bash
.build/debug/kswiftc --stdlib-only --emit jar -o kswiftk-stdlib.jar
.build/debug/kswiftc main.kt helpers.kt --emit jar --classpath kswiftk-stdlib.jar -o app.jar
java -Xverify:all -cp app.jar:kswiftk-stdlib.jar MainKt
kotlinc -no-stdlib -no-reflect -cp kswiftk-stdlib.jar Consumer.kt -d consumer.jar
java -Xverify:all -cp consumer.jar:kswiftk-stdlib.jar ConsumerKt
python3 Scripts/validate_jvm_stdlib.py kswiftk-stdlib.jar app.jar consumer.jar
```

生成JARには実装ソース一覧 `META-INF/kswiftk-stdlib-sources.list` と、既知のtext／collection／Sequence
APIを公開ABIで照合した `META-INF/kswiftk-stdlib-coverage.json` を同梱する。
`jar_abi_present` はowner・method名・descriptorの存在を示し、value-class／JvmName lowering前の仮名は数えない。
これは全stdlibのAPI網羅率ではないため、reportの `complete` はfalseのままとする。

`Scripts/validate_jvm_stdlib.py` は指定したJAR／classディレクトリを読み、Kotlinのclass・method・field参照を照合する。
継承先のJDKメンバーも `javap` の実descriptorで照合し、存在しないメンバーを外部の親があるだけで成功扱いにしない。
この静的検査と、例外・副作用・virtual dispatchを含む実行テストは別の検証である。

`JVMBackendTests.repositoryStdlibRuntimeRegression` は既存M4〜M21の実行例と境界ケースを `.class`／`.jar` の両方で生成し、
生成物と独自stdlibだけのclasspathで期待stdoutと照合する。
`officialKotlinConsumerUsesOnlyRepositoryStdlib` は公式Kotlinによる通常コンパイルと `-no-stdlib -no-reflect` の双方を検証する。
`officialKotlinRuntimeRegression` は同じ実行例を公式Kotlinでもコンパイルし、公式コンパイラのinline展開が残すABI参照も独自JARだけで実行する。
`ownStdlibLazyConcurrencyAndJavaConsumer` はJavaからの並行アクセス、lock、PUBLICATION、再試行、nullを検証する。
`ownStdlibRepeatableContainerMarker` は生成annotation containerのmarkerとRUNTIME retentionをJavaから検証する。

静的検査スクリプト自体のpositive／negative controlは `python3 Scripts/tests/test_validate_jvm_stdlib.py` で実行できる。

公式Kotlinコンパイラは対応済みreflection APIにもkotlin-reflect不在の警告を出すことがある。
この警告とは別に、実際の実行classpathと静的参照閉包を検証する。
