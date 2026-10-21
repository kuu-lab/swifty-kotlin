# JVM バックエンド M22

`kswiftc --emit class|jar` は、Kotlin のサブセットから JVM bytecode を直接生成する。
classfile version は 52（Java 8）。実行には Java 8 以降が必要。
生成処理自体は Swift で完結し、JDK、kotlinc、LLVM、Native Runtime に依存しない。

## 使用例

`hello.kt`:

```kotlin
fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)

fun main() {
    var total = 0
    for (i in 1..5) {
        total += factorial(i)
    }
    println(total) // 153
}
```

```bash
swift build
.build/debug/kswiftc --emit class hello.kt -o classes
java -Xverify:all -cp classes HelloKt

.build/debug/kswiftc --emit jar hello.kt -o hello.jar
java -Xverify:all -jar hello.jar
```

`class` の `-o` は出力ディレクトリ（既定 `./classes`）。`jar` は出力ファイル
（既定 `./main.jar`）を指定する。JAR の親ディレクトリは事前に作成しておく。
ファイル名の先頭を大文字にして `Kt` を付けたクラス名を生成する。
たとえば `package demo` を持つ `hello.kt` は `demo/HelloKt.class` を生成する。
`main(): Unit` がある場合は launcher と Manifest の `Main-Class` を生成する。
`main` のないソースはライブラリとして出力する。

## 対応範囲

- 入力は Kotlin ファイル 1 個。トップレベル関数を複数宣言でき、実行用の `main` は引数なし・Unit 戻り値。ライブラリでは省略できる。
- 型は`Int`、`Long`、`Float`、`Double`、`Boolean`、`String`、`Any` と classpath の参照型。nullable primitive は wrapper に boxing し、参照型とともに `null`、`!!`、`?:` に対応する。関数の戻り値には `Unit` も使用できる。数値／Boolean を `Any` に渡す場合は JVM の wrapper に boxing する。
- ローカル `val` / `var`、型推論、型注釈、代入、数値の `+=` / `-=` / `*=` / `/=` / `%=`、前置／後置 `++` / `--`。型注釈があれば宣言と初回代入を分けられる。
- 数値の `+` / `-` / `*` / `/` / `%`、単項符号、比較。数値型の混合演算と `toInt` / `toLong` / `toFloat` / `toDouble`。
- Boolean の `!` / `&&` / `||` と短絡評価。数値・Boolean・参照型の `==` / `!=`。
- トップレベル関数の位置引数呼び出し、オーバーロード、再帰、`return`、ブロック本体と式本体。
- `if` / `else` の文・式、`while`、`do-while`、Int/Long の `..` / `..<` / `downTo` 範囲による `for`、ラベルなしの `break` / `continue`。
- `print(value)`、`println(value)`、`println()`。対応する値型をそのまま出力できる。
- 通常／raw 文字列リテラル。Unicode、補助文字、NUL、Kotlin のエスケープを保持する。
- package 宣言、`public` / `private` / `internal` の関数。ファイル名（拡張子を除く）・package・クラス名・関数名・プロパティ名・module 名は ASCII 識別子に限定する。

ローカル変数はブロックのスコープを持つ。関数本体ではパラメータを shadow できる。
初期値のないローカルも固定の保存先を持ち、分岐・ループ・例外処理の代入を合流後に読み出せる。
初期化前の読み出し、不完全な経路の初期化、`val` の再代入は共有 Sema で拒否する。
関数型ローカル、closure／匿名 object の capture、suspend をまたぐ保存にも対応する。
ローカルの `Unit` は `kotlin.Unit` オブジェクトとして保存し、関数の `Unit` 戻り値は引き続き JVM の `void` とする。
`do-while` の条件は、その本体で宣言したローカル変数を参照できる。
非 Unit のブロック本体は全経路で明示的に戻る必要がある。ループが常に終了しないことの
証明には対応しないため、ループだけで戻り値を保証する形は拒否する。
整数範囲の終端は一度だけ評価し、inclusive な最終要素では加減算する前に終了を判定する。

## クラス・プロパティ・継承

```kotlin
interface Named {
    val name: String
    fun label(): String = name
}
open class Base(val initial: Int) {
    open fun score(): Int = initial
}
class Counter(var count: Int): Base(count), Named {
    override val name: String = "counter"
    val doubled: Int get() = count * 2
    init { count += 1 }
    constructor(): this(10) { count += 2 }
    override fun score(): Int = super.score() + count
}
fun main() {
    val counter = Counter()
    counter.count = 20
    val base: Base = counter
    println(base.score()) // 30
    val named: Named = counter
    println(named.label()) // counter
}
```

複数の入力ファイルにトップレベル class／interface／関数を宣言し、一つの module として生成できる（M22）。
各型を package に対応する独立した classfile として出力し、JAR にすべて格納する。
通常のクラス、`open`／`abstract`／`final`、メンバーメソッド、`override`、
`this`、`super`、`super<Interface>`、public／protected／internal／private に対応する。
継承先は同じ入力の型、または classpath にある公開クラス／interface を指定できる。

primary／secondary コンストラクタ、`this(...)`／`super(...)` の委譲、
primary コンストラクタの `val`／`var`、初期化ブロック、メンバープロパティの初期化に対応する。
super コンストラクタの実行後、primary property を格納し、宣言順に property initializer と
`init` を実行する。`this(...)` の委譲先で初期化した内容を二重に実行しない。
property initializer／`init` 内の通常のプロパティ読み書きも getter／setter を経由する。

プロパティは private な backing field と getter／setter を生成する。
computed property、custom getter／setter、`field` の参照・代入・数値の複合代入、
`private set` など setter 可視性の制限を扱う。`val` の backing field は読み取り専用で、
必要な初期化時だけ書き込める。field を必要としない computed property には格納領域を生成しない。

interface の抽象メソッド・抽象プロパティと default メソッド・アクセサを生成する。
default 本体は Java 8 の interface メソッドへ直接出力する。
JVM descriptor の戻り型が変わる共変 override には synthetic bridge を生成するため、
基底クラス／interface を介した呼び出しでも実際の override にディスパッチする。

## ジェネリクス・配列・コレクション・例外

```kotlin
class Box<T>(var value: T)
fun <T> identity(value: T): T = value

fun main() {
    val box = Box(21)
    println(identity(box.value) * 2)
    val array = intArrayOf(1, 2, 3)
    array[1] += 10
    val values = mutableListOf(20, 22)
    values.add(array[1])
    for (value in values) { println(value) }
    val counts = mapOf("answer" to 42)
    println(counts["answer"] ?: 0)
    try { println(array[10]) }
    catch (e: IndexOutOfBoundsException) { println("bounds") }
    finally { println("done") }
}
```

非 reified のジェネリック関数・クラス・interface、型引数の明示／推論、
型パラメータごとに1個の上限、宣言側の `in`／`out` と use-site projection に対応する。
JVM descriptor は上限へ型消去し、必要な boxing／unboxing／checkcast を生成する。
`Signature` 属性と Kotlin metadata には型パラメータ・上限・引数を保持するため、
Java／公式 Kotlin からも型付きで利用できる。ジェネリック override の引数変換と
primitive 戻り値の boxing にも synthetic bridge を生成する。型消去後に衝突する
関数のオーバーロードは診断する。

`Array<T>` と `IntArray`／`LongArray`／`FloatArray`／`DoubleArray`／`BooleanArray` に対応する。
`arrayOf`／`arrayOfNulls`／`emptyArray`、各 primitive の `*ArrayOf`、primitive array の
サイズコンストラクタ、`size`、添字の読み書き・複合代入、`get`／`set`、`for` を生成する。
参照配列の要素は JVM の wrapper／参照型となり、多次元配列も使用できる。
配列の要素型は生成時に具体化されている必要があり、非 reified の `T` からの配列生成は拒否する。
`Array<T>(size) { ... }` はreifiedの要素型を保持し、初期化ラムダの非局所return・suspend呼び出しを展開する。
size引数の評価直後に配列を確保し、負サイズ時のinitializer式と名前付き引数の評価順を公式Kotlinに合わせる。
サイズと境界の検査は JVM が行い、対応する例外を catch できる。

`List`／`MutableList`、`Set`／`MutableSet`、`Map`／`MutableMap`、Collection／Iterable／Iterator
を JDK の interface に対応付ける。`listOf`／`mutableListOf`／`setOf`／`mutableSetOf`／
`mapOf`／`mutableMapOf`、`emptyList`／`emptySet`／`emptyMap` を生成する。
factoryと対応済みcollection操作はKotlin JVM ABIに接続し、独自kswiftk-stdlib.jarで実行できる。
`to` は kotlin.Pair を生成し、factory 以外でも利用できる。
添字、`size`、`isEmpty`、`contains`／`containsAll`、`add`、`remove`／`removeAt`、`set`／`put`、`clear`、
Map の `keys`／`values`／`entries`／`containsKey` と iterable の `for` を利用できる。
Map の取得結果は nullable なので、`!!`／`?:` で値を取り出せる。

`throw` と、値を返す `try`／複数の `catch`／`finally` を JVM の exception table へ変換する。
Throwable／Exception／RuntimeException と主要な標準例外、引数なし／String? 引数のコンストラクタ、`message`、ユーザー定義の例外クラスを扱う。
Throwable／Exception／RuntimeException には Throwable? 引数と String?／Throwable? 引数のコンストラクタもある。
`finally` は通常終了、例外、`return`／`break`／`continue` で実行し、内部の同名変数や
ループに影響されず字句的な参照先を保持する。`finally` 内の return／throw は元の結果を置き換える。
コンストラクタ引数内の try/catch でも初期化前の参照を JVM verifier に合わせて保持する。
`is`／`as`／`as?` は erased JVM 型の instanceof／checkcast を使用する。

## ラムダ・クロージャ・高階関数・拡張関数

```kotlin
fun apply(value: Int, operation: (Int) -> Int): Int = operation(value)
fun counter(start: Int): () -> Int {
    var current = start
    return { current += 1; current }
}
fun Int.withOperation(block: Int.() -> Int): Int = block()

fun main() {
    val scale = 3
    println(apply(14) { it * scale }) // 42
    val next = counter(8)
    println(next()) // 9
    println(next()) // 10
    println(20.withOperation { this + 22 }) // 42
    val values = IntArray(3) { index -> index + 1 }
    println(values.map { it * 2 }.fold(0) { sum, value -> sum + value }) // 12
}
```

関数型のローカル・引数・戻り値・メンバープロパティ、ラムダの明示／暗黙の `it`、
末尾ラムダ、関数値の `f(...)`／`f.invoke(...)`、直後のラムダ呼び出しに対応する。
外側のローカル・パラメータ・`this` を capture でき、返されたラムダも環境を保持する。
可変ローカルは共有セルを通すため、複数のクロージャや元のスコープからの変更が共有される。
入れ子のラムダ、ループごとの capture、private なメンバーへの参照も扱う。
ラベル付きラムダと `return@label`／`return@関数名` は、そのラムダ内の return に対応し、
`finally` も実行する。inline 引数のラムダでは外側の関数へ抜ける non-local return も扱う。

トップレベル／メンバーの拡張関数、nullable／generic receiver、receiver 付き関数型、
`this@label` に対応する。拡張 receiver は JVM signature の先頭引数へ変換し、
メンバー拡張関数では dispatch receiver を別に保持する。
Kotlin metadata は拡張 receiver と `ExtensionFunctionType` を記録する。
公式 Kotlin からは拡張構文と receiver lambda、Java からは receiver を明示した呼び出しを使用できる。

Iterable／Array／対応する primitive array の `map`／`filter`／`forEach`／`fold`、
`Array<T>(size) { ... }` と primitive array の initializer lambda を生成する。
`map`／`filter` の結果は List として返す。callback を一度評価し、各要素を順に処理する。

ラムダクラスは `kotlin.jvm.functions.Function0`〜`Function22` を実装し、
型消去した `invoke(Object...): Object` で boxing／unboxing する。Unit 戻り値は
`kotlin.Unit.INSTANCE` を返す。必要な Function interface と Unit singleton を生成物に同梱するので、
ラムダを含む JAR も実行できる。コレクション操作にはkswiftk-stdlib.jarをclasspathに追加する。
公式 stdlib を使う consumer とも同じ ABI で接続する。
Java consumer は `Function1<Integer, Integer>` などの Java lambda を高階関数へ渡せる。

## object・companion・data・enum・sealed

名前付き `object` は private constructor と public static final な `INSTANCE` を持つ class に変換する。
初回アクセス時に JVM のクラス初期化で singleton を作り、プロパティと init を宣言順に実行する。
singleton を公開してから本体を初期化するため、init 内から自身を参照できる。通常のクラスの継承、
interface の実装、private メンバー、init 内での val の代入も利用できる。

companion object は `Outer$Companion`（名前付きなら `Outer$Named`）に生成し、
外側の class／interface に同名の static final フィールドを置く。Kotlin では `Outer.create()`、
Java では `Outer.Companion.create()` で呼べる。Java 8 に合わせて、入れ子の class から private な
constructor／method／field を使う場合は synthetic access bridge を生成する。
`InnerClasses` と Kotlin metadata には外側の型と companion 名を記録する。

```kotlin
class Factory private constructor(val value: Int) {
    companion object { fun create(value: Int): Factory = Factory(value) }
}
data class Point(val x: Int, var label: String)
enum class Mode(val code: Int) { FIRST(20), SECOND(22) }
sealed class Shape {
    data class Circle(val radius: Int): Shape()
    object Empty: Shape()
}
fun area(shape: Shape): Int = when (shape) {
    is Shape.Circle -> shape.radius * 2
    Shape.Empty -> 0
}
fun main() {
    println(Factory.create(42).value)
    println(Point(21, "left").copy(x = 42))
    println(Mode.entries[1].name)
    println(area(Shape.Circle(21)))
}
```

data class は primary constructor のプロパティから `componentN`、`copy`、`copy$default`、
`equals`／`hashCode`／`toString` を生成する。copy の名前付き／省略引数、data class の
ローカル val／var の destructuring、generic なプロパティにも対応する。クラス本体のプロパティはこれらの生成対象に含めない。
Float／Double の比較では NaN と符号付きゼロを Kotlin の data class と同じように扱う。
配列は equals では参照比較、hashCode／toString では内容を使う。ユーザー定義の override は保持する。

enum class は `java.lang.Enum<E>` を継承し、name／ordinal、定数フィールド、constructor、
`values()` の配列コピー、`valueOf(String)`、読み取り専用の `entries` を生成する。
定数ごとの本体はサブクラスにし、method／property の override と init を実行する。
EnumEntries interface と読み取り専用 List 実装は生成物に同梱し、公式 stdlib と同じ ABI を使う。
enum の companion は定数の初期化後に初期化する。

sealed class／interface は abstract な JVM 型として生成し、Kotlin metadata に sealed modality と
直接のサブクラスを記録する。static な nested class／object も利用できる。
subject のある／ない when、複数の条件、型判定・smart cast、nullable 型、網羅的な enum／sealed の
分岐を生成する。Java／公式 Kotlin から生成した型を使い、公式 Kotlin 側でも網羅性を検査できる。
classfile 52 を維持するため JVM の PermittedSubclasses 属性は使わず、sealed の制約は Kotlin の意味解析と
metadata による。M8 のこれらの機能だけなら kotlin-stdlib.jar は不要。

## SAM 変換・inline・suspend

`fun interface` と classpath 上の Java SAM interface に対し、ラムダ／関数値からの変換、
`Op { ... }` 形式のコンストラクタ呼び出し、引数位置での暗黙変換を生成する。
生成 adapter は対象 interface の抽象メソッドを実装し、継承した default メソッドを利用できる。
generic SAM は消去した引数・戻り値へ boxing／unboxing する。suspend 抽象メソッドも扱う。

```kotlin
fun interface Op { fun apply(value: Int): Int }
inline fun apply(value: Int, block: (Int) -> Int): Int = block(value)
fun early(): Int { apply(21) { return it * 2 }; return 0 }
fun main() {
    val op = Op { it * 2 }
    println(op.apply(21)) // 42
    println(early()) // 42
}
```

ユーザー定義 inline 関数は呼び出し位置へ本体を展開し、通常のラムダ引数も直接展開する。
引数の評価順、capture、receiver、ラムダの局所 return／関数の非局所 return、finally を保持する。
`noinline` と `crossinline` は通常の関数値として保持し、非局所 return は Sema が拒否する。
外部 Kotlin 向けには crossinline 引数も noinline として記録し、lift したラムダへの関数値を保持する。
そのため、別モジュールから crossinline パラメータを再転送する最適化や修飾の reflection は扱わない。
公開関数には inline／パラメータ修飾の Kotlin metadata を出力し、公式 Kotlin consumer の
bytecode inliner からも利用できる。再帰 inline は拒否する。reified と inline suspend は M15 で対応する。

`suspend fun` は隠し `Continuation<? super R>` 引数と `Object` 戻り値の JVM ABI へ変換する。
呼び出しごとの状態クラスがローカル変数・capture・再開位置を保存し、
`COROUTINE_SUSPENDED` を返して呼び出し元へ制御を戻す。再開後は途中の式・ループを続け、
`resumeWithException` の失敗も source の catch／finally で処理する。
継承／interface の suspend メソッド、generic bridge、receiver 付き suspend 関数型、suspend SAM、
引数なしの `suspend fun main()` に対応する。Java／公式 Kotlin からも同じ Continuation ABI で呼べる。

起動・中断には `kotlin.coroutines` の `Continuation`、`EmptyCoroutineContext`、
`startCoroutine`、`suspendCoroutine`、`resume`／`resumeWithException`／`resumeWith` を使える。
`Result<T>` の `getOrThrow`／`isSuccess`／`isFailure`／`exceptionOrNull` も利用できる。

```kotlin
import kotlin.coroutines.*
suspend fun twice(value: Int): Int = suspendCoroutine { it.resume(value * 2) }
suspend fun main() { println(twice(21)) }
```

suspend出力は独自kswiftk-stdlib.jarのContinuationImpl／SafeContinuation／Resultを使用する。
コンパイル時の stdlib 指定は不要だが、実行時は classpath に追加する。外部の kotlinx.coroutines は不要。
公開 inline entry を Java などから直接呼び出す場合も、標準の引数検査に stdlib を使用する。
ソース内だけで inline 展開する通常のプログラムは従来どおり単独で実行できる。

```bash
kswiftc --emit jar hello.kt -o hello.jar
java -Xverify:all -cp "hello.jar:kswiftk-stdlib.jar" HelloKt
# .class 出力の場合
java -Xverify:all -cp "classes:kswiftk-stdlib.jar" HelloKt
```

`java -jar` は追加 classpath を参照しないので、suspend 出力は上記のように facade 名を指定する。
独自 CoroutineContext 実装、Result の生成、kotlinx.coroutines の builder／Job／dispatcher／cancellation、
coroutine reflection／debug metadata、外部 JAR の suspend metadata 読み込みは対象外。
初期化前のコンストラクタ引数からの中断は診断して拒否する。

## Java／公式 Kotlin からライブラリを呼ぶ

`api.kt`:

```kotlin
package demo
fun add(left: Int, right: Int): Int = left + right
fun echo(text: String): String = text
```

```bash
kswiftc --emit jar api.kt -o api.jar
```

Java は `demo.ApiKt.add(20, 22)`、公式 Kotlin は `import demo.add` で呼び出せる。
Kotlin の consumer では `add(right = 22, left = 20)` のような名前付き引数も使用できる。

```bash
javac -cp api.jar JavaConsumer.java
java -cp .:api.jar JavaConsumer
kotlinc -cp api.jar Consumer.kt -include-runtime -d consumer.jar
java -cp consumer.jar:api.jar ConsumerKt
```

`kotlin.Metadata`（metadata version 2.0）と `META-INF/<module>.kotlin_module` に、
関数・クラス・コンストラクタ・プロパティの名前、JVM signature、引数名、可視性、
modality、nullability を記録する。生成クラスは公式 Kotlin からコンストラクタの
名前付き引数とプロパティ構文で利用でき、生成interfaceを実装して default メソッドを継承できる。
`internal` は Kotlin consumer から利用できず、private メンバーは JVM でも private となる。
private なトップレベルクラスの classfile は package-private とする。
JVM の `internal` メソッド自体は public なので Java からはアクセスできる。
非 nullable 参照引数には、Java から null が渡された場合の NPE 検査を生成する。

## KSwiftK から外部 JAR を呼ぶ

Java の `dep.Counter` が `public Counter(int)`、`public int add(int)`、
`public static int twice(int)` を持つ場合:

```kotlin
import dep.Counter
fun main() {
    val counter = Counter(10)
    println(counter.add(3))
    println(Counter.twice(5))
}
```

```bash
kswiftc --emit jar --classpath deps.jar app.kt -o app.jar
java -Xverify:all -cp app.jar:deps.jar AppKt
```

`--classpath`（別名 `-classpath` / `-cp`）は `:` 区切りで JAR／class ディレクトリを指定する。
繰り返し指定でき、先の entry にある同名クラスを優先する。空の区間はカレントディレクトリ。
依存 JAR は出力に同梱しないため、実行時にも `java -cp` へ渡す。
JDK のクラスは自動検索しない。参照先の宣言に必要な依存クラスも classpath に明示する。

public なトップレベルクラス／interface のコンストラクタ・static／instance／interface
メソッドと、公開 superclass／interface 経由の継承メソッドに対応する。
非公開 superclass／interface から継承する public メソッドも、アクセス可能な公開クラスを
JVM 呼び出しの owner として利用できる。非公開の型や protected／package-private メンバーは公開しない。
import alias、オーバーロード、参照型の引数・戻り値も使用できる。
公式 Kotlin が生成したクラスも Java の JVM signature として読み込める。
KSwiftK 生成のファイル facade は `import demo.ApiKt` → `ApiKt.add(...)` で再利用できる。
外部 Kotlin JAR の metadata は import 時には解釈せず、Java の公開 ABI として扱うため、
トップレベル関数も facade クラスを介して呼び出す。

Java の参照 signature は platform 型として扱い、推論した公開戻り型にも flexible 型を記録する。
非 nullable のローカルや戻り値へ変換する境界と `!!` は NPE 検査を行う。
メソッドの型引数・annotation による nullability は解釈せず、JVM の erased signature を使う。
配列 signature は primitive array／Array に対応付ける。classpath にない参照型を含む外部メソッドは公開しない。

## 匿名 object・data object・inner class・引数（M9）

匿名 object は式を評価するたびにインスタンスを生成する。superclass／interface、独自メソッド・property・init、
外側のローカル変数と receiver の capture に対応する。可変ローカルは lambda と同じセルを共有し、
作成元の関数が戻った後も読み書きできる。capture field は super 呼び出しより先に設定する。
型を明示しない公開／internal／protected な関数・property では、匿名型を単一の supertype（なければ Any）に
変換する。複数の supertype がある公開 API は型の明示が必要となる。private／ローカルでは独自メンバーを保持する。

data object は通常の singleton に加え、同じ生成クラスのインスタンスを等しいとする equals、
完全修飾名から求める一定の hashCode、単純名の toString を生成する。継承した final toString と
ユーザーが定義した toString は保持する。

inner class は synthetic final な this$0 と、outer instance を先頭に受け取る constructor を持つ。
`outer.Inner(...)`、暗黙の outer、`this@Outer`、複数段の inner、外側の private member に対応する。
InnerClasses 属性の static flag を外し、Kotlin metadata の inner flag を記録する。

```kotlin
class Outer(private val value: Int) {
    inner class Inner(val extra: Int = value) {
        fun total(offset: Int = 2): Int = value + extra + offset
    }
}
data object Done
fun main() {
    val outer = Outer(20)
    println(outer.Inner().total()) // 42
    println(outer.Inner(extra = 10).total(offset = 12)) // 42
    var n = 40
    val counter = object { fun next(): Int { n++; return n } }
    println(counter.next()) // 41
    println(Done) // Done
}
```

名前付き引数は記述順に評価してから parameter 順に並べ替える。デフォルト式は、明示した引数の評価後に
宣言順で評価する。先行 parameter／receiver の参照、末尾 lambda、継承した既定値、primary／secondary
constructor とその委譲、object／enum の初期化、extension／inline／suspend に対応する。
32 parameter ごとの mask を持つ function$default と、mask／DefaultConstructorMarker を末尾に受け取る
constructor を生成し、metadata に既定値フラグを記録する。全 primary parameter が省略可能なら
Java 用 noarg constructor も生成する（inner／enum と、明示的な noarg constructor がある場合を除く）。
Java は通常の全引数メソッド／constructor を呼べる。公式 Kotlin は名前付き引数と省略引数を利用できる。
suspend の default bridge では Continuation が mask より前に位置する。
外部 JAR の import は従来通り erased JVM signature であり、その Kotlin metadata から parameter 名や
デフォルト式を取り込む機能は含まない。

## クラス委譲・委譲プロパティ・lazy・lateinit（M10）

```kotlin
interface Counter { fun next(): Int }
class Implementation: Counter { override fun next(): Int = 42 }
class Forward(delegate: Counter): Counter by delegate

val answer: Int by lazy { 42 }
lateinit var status: String
class Holder {
    val value: Int by lazy(LazyThreadSafetyMode.PUBLICATION) { 42 }
    lateinit var text: String
    fun ready(): Boolean = this::text.isInitialized
}
fun main() {
    println(Forward(Implementation()).next())
    println(answer)
    println(::status.isInitialized) // false
    status = "ready"
    println(status)
}
```

interface のクラス委譲は、delegate 式を宣言順に一度だけ評価して専用フィールドに保存する。
通常 class、object、匿名 object、複数の interface、明示 override、継承 default method、
既定引数、generic method／property、member extension method と bridge に対応する。
constructor parameter の `var` を後で変更しても、保存済みの委譲先は変わらない。
委譲先内部のメソッド呼び出しは、その委譲先自身の receiver へディスパッチする。
`List`／`MutableList`、`Set`／`MutableSet`、`Map`／`MutableMap` の `by` 委譲では、
JDK interface の型消去された bridge と `toArray` などの追加エントリも生成する。
`toArray` はクラス自身の `size`／`iterator` の override を反映する。
read-only の `add`／`remove`／`set`、`sort`、Map の `compute` などは
`UnsupportedOperationException` を投げる。`removeIf` は JDK の既定実装に従う。
Kotlin の可変 collection 判定に必要な marker interface も保持する。

メンバー・トップレベル・ローカルの `val`／`var` に `by` を使用できる。
独自の operator getValue／setValue／provideDelegate、トップレベル／メンバーの extension operator、
ReadOnlyProperty／ReadWriteProperty、Delegates.notNull／observable／vetoable を扱う。
provideDelegate は宣言の初期化時に呼び、その戻り値を保存する。getValue／setValue には
member の this（トップレベル／ローカルは null）と、名前を保持する公式 KProperty 参照を渡す。
var には mutable な参照を使用し、各 property の token を getter／setter 間で共有する。
ローカルの delegate はラムダ／匿名 object へ capture できる。
property reference の一般的な生成・呼び出しや、ローカル property の reflection、および KProperty／KMutableProperty の独自実装は対応範囲に含まない。

lazyは独自stdlibの実装を利用する。初回取得まで initializer を実行せず、成功した結果を
null を含めて保存する。例外の後は再試行する。SYNCHRONIZED（既定）／PUBLICATION／NONE、
lock 引数の overload、Lazy.value／isInitialized に対応する。
トップレベル・メンバー・ローカルの lateinit var は、参照型の null sentinel を保持し、
未初期化なら標準の UninitializedPropertyAccessException を property 名付きで投げる。
member／top-level の property literal に対する `::property.isInitialized` も扱う。
Java からは通常の getter／setter を使用でき、lateinit の公開 backing field も利用できる。
公式 Kotlin は property 構文と生成した delegate class の operator を利用できる。

トップレベル property も facade の static field／accessor と clinit に生成し、
通常の initializer／custom accessor と package property metadata を保持する。

委譲propertyのKProperty token、lazy、lateinit例外も独自stdlibから供給する。
生成 JAR に stdlib は内包しない。実行例（環境に応じて stdlib のパスを指定）：

```bash
.build/debug/kswiftc --emit jar hello.kt -o hello.jar
java -Xverify:all -cp "hello.jar:/path/to/kswiftk-stdlib.jar" HelloKt
```

## M11: value class・typealias・annotation・reflection

`@JvmInline value class` の単一の保存値、メソッド、interface 実装、初期化処理、nullable、
Any／型パラメータ／collection への boxing を扱う。公開メソッドには公式 Kotlin と同じ
MD5 による名前修飾と unboxed descriptor を生成する。`constructor-impl`、`box-impl`、
`unbox-impl`、equals／hashCode／toString と `equals-impl0` を生成し、box 時には init を再実行しない。
通常のクラスが value class をコンストラクタ引数に持つ場合は marker constructor を公開する。
Kotlin metadata は source の型と名前を保ち、Java／公式 Kotlin の consumer が生成 JAR を利用できる。
内部の式は boxed IR を使い、公開 ABI の adapter が unbox／box を担当する。

`typealias` は共有 Sema で展開し、型パラメータと展開型を package／class metadata に保存する。
別の classfile は生成しない。関数・getter の JVM signature と source の alias の情報を分けて保持する。

source の annotation class は Java annotation interface として出力する。Int／Long／Float／Double／
Boolean／String、enum、KClass、入れ子の annotation、これらの配列と annotation の vararg を扱う。
既定値は AnnotationDefault、使用箇所は RuntimeVisibleAnnotations／RuntimeInvisibleAnnotations／
parameter annotations に保存し、SOURCE retention は出力しない。Kotlin／Java 両方の Retention／Target と
MustBeDocumented を記録する。class／function／constructor／parameter、field／get／set／property／
param／setparam の use-site target、property の `$annotations` carrier、`@JvmName` に対応する。
annotation 引数には primitive／String の定数式と const val を使える。トップレベル／named object／companion の const field は ConstantValue を持つ。class companion の const field は外側のクラスへ配置し、interface companion は外側とcompanion双方へ配置する。直接参照は定数値、独自reflection runtimeのプロパティ参照はそのfieldを読み出す。

`Type::class`／`value::class`、bound／unbound な関数・コンストラクタ・property 参照を生成する。
class literal は ldc を使い、対象クラスの static initializer を実行しない。
KClass の名前・フラグ・isInstance・members／constructors、KCallable の name／parameters／returnType／call、
property の get／set、`kotlin.reflect.full` の memberProperties／memberFunctions／createInstance／findAnnotation、
`.java`／`.kotlin`／`.javaClass` と Class.getAnnotation を独自stdlibのJDK連携へ接続する。
KCallable の returnType.toString は metadata の Kotlin 型名、nullability、型引数・projection、
関数型と型パラメータ名を表示する。constructor の戻り型も Kotlin のクラス名を返す。

```kotlin
import kotlin.reflect.full.findAnnotation

annotation class Label(val text: String)
@Label("distance") @JvmInline value class Meter(val value: Int)
typealias Distance = Meter
fun twice(m: Distance): Distance = Meter(m.value * 2)

fun main() {
    val function = ::twice
    println(function(Meter(21)))
    println(Meter::class.findAnnotation<Label>()!!.text)
}
```

```bash
.build/debug/kswiftc --emit jar hello.kt -o hello.jar
java -Xverify:all -cp "hello.jar:kswiftk-stdlib.jar" HelloKt
```

参照の生成、クラスのフラグ・メンバー列挙・annotation・reflective call・propertyのget／set・関数参照のinvokeは、独自stdlibのJava reflection／metadata実装を使う。生成JARとkswiftk-stdlib.jarを実行classpathへ指定する。

annotation の値は constructor 式で直接生成できる。省略した引数には annotation element の default を使い、
名前付き引数もソース順に評価する。生成する値は annotation interface を実装し、要素の読み取り・等値比較に対応する。

value class を持つ inline／suspend の signature は M14 で対応する。
外部 annotation の使用、file／type-use／receiver／delegate target、
typealias 自体の annotation、enum entry annotation は未対応。対応する reflection API は上記の範囲で、
Java reflection の任意の getMethod／invoke や kotlin-reflect の全 API を提供するものではない。

## M12: generic value class・repeatable annotation

`@JvmInline value class Box<T>(val value: T)` を生成する。`Box<Int>` の保存値も宣言上の上限型
（既定は Object）へ消去する。Any／Number／String／interface の上限、nullable、generic method、
collection、配列を型引数とする場合、ラムダ／匿名 object への capture を扱う。
nullable value class は、保存値が null を取り得る場合は boxed class、非 null reference の場合は
nullable な underlying reference を公開 ABI に使用する。field／getter／constructor-impl と adapter の
Signature は型変数と underlying の型引数を保持し、公式 Kotlin consumer は metadata から source 型を復元する。
配列／別の value class の underlying、secondary／default constructor は M13 で対応する。
value class を持つ inline／suspend の signature は M14 で対応する。

`@Repeatable` は公開ネスト annotation `Tag$Container` を生成し、`value(): Tag[]`、元 annotation と同じ
Retention／Target／MustBeDocumented、RepeatableContainer marker、Kotlin metadata を保存する。
元 annotation には Kotlin Repeatable と Java Repeatable を付け、単一使用は直接、複数使用は container に格納する。
SOURCE は使用箇所に出力せず、BINARY は不可視属性、RUNTIME は可視属性へ保存する。
`@kotlin.jvm.JvmRepeatable(Tags::class)` は source の明示 container を使う。`value: Array<Tag>`、
他の要素の既定値、元 annotation 以上の retention、元 annotation の部分集合となる target を検査する。
Repeatable との併用時は明示 container を優先する。
`kotlin.reflect.full.findAnnotations<T>()` と Java `Class.getAnnotationsByType` は両方の container に対応し、
自動 container は KClass.annotations でも各 annotation へ展開される。実行にはkswiftk-stdlib.jarを使用する。

```kotlin
import kotlin.reflect.full.findAnnotations

@JvmInline value class Box<T>(val value: T)
@Repeatable annotation class Tag(val value: String)
@Tag("one") @Tag("two") class Marked

fun main() {
    val box = Box(21)
    val read = { box.value }
    println(read())
    println(Marked::class.findAnnotations<Tag>()[1].value)
}
```

## M13: 配列／入れ子の value class・constructor

value class の保存値に primitive array／参照型 array／generic array と、別の value class を使える。
入れ子は再帰的に物理型へ展開し、nullable underlying と nullable boxed value の区別を保持する。
保存 field、getter、constructor、公開メソッドの descriptor／Signature と metadata を対応させる。
underlying getter は instance のまま、戻り値が value class の場合は公式の名前修飾を付ける。
generic array の field／getter は T[]、公開メソッドの物理型は消去後の Object[] を使う。
配列の equals は参照を比較し、hashCode／toString は Arrays.hashCode／Arrays.toString へ接続する。
入れ子の hashCode／toString は内側の value class の意味を保つ。

primary／secondary constructor は static constructor-impl を公開する。
どちらも既定引数と名前付き引数、先行引数を参照する既定式、複数 mask、委譲 chain に対応し、
既定式・委譲引数・primary init・内側から外側の secondary body の順を保持する。
既定引数用の constructor-impl$default は mask と DefaultConstructorMarker を受け取る。
metadata は secondary と optional parameter の flags を持ち、Java／公式 Kotlin consumer が利用できる。
boxed な内部 constructor と、init を実行しない保存専用 constructor を分けるため、boxing で init を再実行しない。
独自reflectionによる明示引数を渡すconstructor.callに対応する。既定値を省略する callBy は、
公式 Kotlin 2.4.20 の value class でも対応していないため、対応範囲には含めない。
Native 向けの value-class secondary constructor の制限は継続する。

```kotlin
@JvmInline value class Numbers(val value: IntArray)
@JvmInline value class Wrapped(val value: Numbers = Numbers(intArrayOf(1, 2))) {
    constructor(a: Int, b: Int): this(Numbers(intArrayOf(a, b)))
}
fun main() {
    println(Wrapped())
    println(Wrapped(3, 4))
}
```

M11と同様に`--emit class|jar`で生成し、kswiftk-stdlib.jarをclasspathへ追加する。
再帰する value-class 保存型は未対応。value class を持つ inline／suspend の signature は M14 で対応する。

## M14: value class を持つ inline／suspend

inline 関数の引数・戻り値・extension receiver に value class を使える。
公開メソッドは通常の value-class ABI と同じ物理型・名前修飾を使い、本体の local／label／exception handler を
ABI adapter へ写す。callback の invoke を保持するため、別 package の公式 Kotlin consumer でも
ラムダの展開、non-local return、finally、既定引数が動作する。primitive／wide／reference／generic／nullable と
value class 自身の inline member、noinline／crossinline の capture を扱う。

suspend 関数も引数と receiver を物理型へ展開し、名前修飾には末尾の Continuation を含める。
physical return は Object、Continuation の generic Signature と metadata は source の logical 型を保つ。
primitive を保存する value class は同期復帰も boxed value を返す。
reference を保存する場合は、同期復帰は raw underlying、遅延 resume は boxed value を渡す。
nullable value class と nullable underlying の違い、COROUTINE_SUSPENDED、例外と finally を保持する。
内部 coroutine worker は logical box を使い、公開 wrapper と default bridge が同期 return を変換する。
interface／override／value class 自身の member、extension、generic、既定引数にも対応する。

suspend callable referenceはContinuationを含むFunctionNとして生成し、独自stdlibのKCallables.callSuspendへ接続する。実行classpathにはkswiftk-stdlib.jarを追加する。value-class constructor の内部 box は引数の評価後に確保するため、
`V(awaitInt())` のように引数で suspend できる。通常のクラスの未初期化 constructor 引数内の suspension は未対応。
`inline suspend` の組み合わせと reified は M15 で対応する。

```kotlin
@JvmInline value class V(val value: Int)
inline fun apply(v: V, block: (V) -> V): V = block(v)
suspend fun echo(v: V = V(21)): V = v
suspend fun main() {
    val result = echo()
    println(apply(result) { V(it.value * 2) })
}
```

M11 と同じ `--emit class|jar` と独自stdlib の classpath 指定で生成・実行する。
生成 JAR の inline／suspend は Java と別 package の公式 Kotlin consumer からも利用できる。

## M15: inline suspend と reified

inline suspend 関数は、Java から実行できる通常の coroutine entry と、公式 Kotlin の
bytecode inliner 向けの `$$forInline` 本体を生成する。Continuation を末尾へ追加し、
suspend 呼び出しの前後へ InlineMarker 0／1 を置く。既定引数 stub も展開用の本体を持つ。
callback の展開、non-local return、finally、遅延 resume に対応する。
reference を保存する value class の同期 return と boxed resume は marker 8／9 で区別する。

`inline fun <reified T>` と `inline suspend fun <reified T>` は、型引数の推論／明示指定、
`is`／`!is`、`as`／`as?`、`T::class`、`arrayOfNulls<T>` などの配列生成、別の reified 関数への
型引数の転送に対応する。nullable、primitive の wrapper class、value class、配列型への転送も扱う。
型判定・cast・class literal・配列生成を使う escaping lambda は Class・nullable・可変collection種別の情報を capture し、
返却後も実行できる。ソース内の inline 展開は具体型を使い、公開 bytecode は
reifiedOperationMarker 0〜4 と Kotlin metadata の reified flag を出力する。
別 JAR の公式 Kotlin consumer もこれらの関数を展開できる。

```kotlin
inline fun <reified T> matches(value: Any?): Boolean = value is T
suspend fun fetch(): Any = "ready"
inline suspend fun <reified T> fetchMatches(): Boolean = matches<T>(fetch())
suspend fun main() {
    println(fetchMatches<String>())
}
```

M14 と同じ CLI と独自stdlib の classpath 指定で生成・実行する。
reified の公開メソッドは synthetic な展開用 bytecode で、Java／reflection による直接実行はサポートしない。
通常の inline suspend は Continuation を渡して Java から呼べる。
inline suspend の synthetic `$default` は公式 Kotlin の展開用であり、遅延 suspension を伴う直接実行は対象外。
非 reified 型パラメータを reified 引数に渡すプログラムは診断し、既存出力を保持する。

## M16: reified 関数参照と匿名 object の型情報 capture

`::function`、bound／unbound の member／extension 参照は、期待する関数型とreceiverから
reified 型引数を推論し、専門化した本体を持つhelperを呼び出す。
Kotlinと同じく `::function<String>` ではなく、`val f: (Any?) -> String = ::cast` のように型を与える。
外側のreified関数から返す参照はClass・nullable・可変collection種別の情報をcaptureし、返却後も型判定・cast・class literal・
配列生成を実行する。既定引数内だけで使う型情報も保持する。
primitive／nullable／配列／value class、suspend関数参照、SAM変換にも対応する。

通常の参照はFunctionReferenceImplを継承し、reflectionでは元のgeneric関数の名前・型パラメータ・
reified情報・Signatureを示す。invokeは専門化helperを実行するが、reflectionのcallは元の関数を呼ぶ。
元のbodyがreified markerを必要とする場合、公式Kotlinと同じくreflectionからの直接呼び出しは失敗する。
既定引数省略、Unitへの変換、非suspendからsuspendへの変換を伴う参照はAdaptedFunctionReferenceを使い、
KFunctionとしては扱わない。bound receiverは参照の生成時に一度だけ評価する。

匿名objectもClass・nullable・可変collection種別の情報をconstructorからfieldへ保存する。
initializer・getter・method・入れ子のラムダ／object・関数参照・suspend復帰後から型情報を利用できる。
super constructorの引数は外側の型情報で評価し、通常値とmutable cellのcaptureも保持する。
inline展開のsiteごとに匿名objectのsubclassを生成し、公開inlineのclassとconstructorは
別packageからアクセスできる。公式Kotlinのbytecode inlinerにも必要なclass reification markerを渡す。

```kotlin
inline fun <reified T> cast(value: Any?): T = value as T
inline fun <reified T> reference(): (Any?) -> T = ::cast
interface Check { fun matches(value: Any?): Boolean }
inline fun <reified T> check(): Check = object: Check {
    override fun matches(value: Any?): Boolean = value is T
}
fun main() {
    val text: (Any?) -> String = ::cast
    println(text("ready"))
    println(reference<Int>()(42))
    println(check<String?>().matches(null))
}
```

M15と同じCLIで.class／JARを生成する。関数参照とreflectionもkswiftk-stdlib.jarを使用する。
生成JARを別packageの公式Kotlinからinline展開でき、通常の公開factoryを通じてJavaからも利用できる。

## M17: Char・Byte・Short・unsigned 型

CharはUTF-16の1 code unitとして扱い、`C` descriptor、Characterによるboxing、
`code`・Char同士の比較／差・Intとの加減算・inc／dec・Char rangeを生成する。
Byte／Shortは`B`／`S` descriptorとByte／Short wrapperを使い、演算時はKotlinの規則でIntへ昇格する。
明示的な型変換とinc／decでは8／16 bitへ切り詰める。Int.toCharは16 bitへ切り詰め、
Char(code)は0〜65535以外をIllegalArgumentExceptionで拒否する。
PrintStream／StringBuilderのByte／Short引数は、実在するInt overloadへ変換して呼び出す。

UInt／ULong／UByte／UShortはそれぞれ`I`／`J`／`B`／`S`を保存形式に使う。
演算・比較は符号なしの意味を保ち、UInt／ULongの除算・剰余・比較にはJDKのunsigned命令相当を使う。
UByte／UShortは昇格前にゼロ拡張し、結果をKotlinと同じUIntまたはULongとして扱う。
bitwise and／or／xor／inv、shl／shr、桁あふれ、符号付き整数との明示的変換にも対応する。
Float／DoubleからUInt／ULongへの変換には独自stdlibの飽和処理を使い、NaN・負値・無限大を扱う。
`MIN_VALUE`／`MAX_VALUE`／`SIZE_BITS`／`SIZE_BYTES`も利用できる。

CharArray／ByteArray／ShortArrayとunsignedの4種類の配列は、対応するprimitive arrayを生成する。
factory・size／initializer付きconstructor・get／set・反復と、既存のmap／filter／forEach／foldを利用できる。
unsigned配列をAnyやgeneric型へ渡すときは公式のUIntArray等へboxingし、nullableのnullを保持する。
通常の表示とdata／value classの表示には`UIntArray(storage=[-1, 1])`等のKotlin表現を使う。

unsigned scalarのnullable型、generic／collection／lambdaの引数・戻り値では公式の
`kotlin.UInt`／`ULong`／`UByte`／`UShort` wrapperを使う。
公開関数・member・accessor・default bridgeはKotlinのvalue-class名修飾に従う。
符号付き型とunsigned型の関数overload、`@JvmName`によるJava向けの名前指定にも対応する。
コンストラクタは必要なDefaultConstructorMarkerを公開する。同じ消去signatureになるconstructorは診断する。
Java classpathの`C`／`B`／`S`およびそれらの配列descriptorも読み込む。

inline／reified／関数参照・value class・suspendと組み合わせて使用できる。
suspend scalarの戻り値とContinuationの型引数は論理型のwrapperを保つ。
unsigned配列のsuspendは同期returnでraw配列、resumeで公式wrapperを運び、nullable変換と
inline suspendのresume markerにも対応する。unsignedのboxing・変換も独自stdlibから供給する。

```kotlin
fun half(value: UInt = UInt.MAX_VALUE): UInt = value / 2u
fun main() {
    val letter: Char = '界'
    val tiny: Byte = 127
    println(letter.code)
    println((tiny + 1).toByte())
    println(half())
    println(ULong.MAX_VALUE / 2uL)
    val values = ubyteArrayOf(0u, 255u)
    println(values[1].toInt())
}
```

M16と同じCLIで.class／JARを生成し、kswiftk-stdlib.jarをclasspathへ加えて実行する。

## M18: String の連結・テンプレート・基本操作

String の `+`／`+=`、Char と String の連結、nullable String の `plus`、
`$name`／`${expression}`、通常／raw／multi-dollar テンプレートを生成する。
各補間式は評価直後に StringBuilder へ append し、副作用・例外・return の順序を保つ。
Unit は式の副作用を実行して `kotlin.Unit`、null は `null` と表示する。
unsigned／value class は Kotlin の論理型で表示し、配列は Object の文字列表現を使う。
ローカル・プロパティ・配列／List／Map 要素の `+=` と mutable capture にも対応する。

主な基本操作は次のとおり。

- `length`／`lastIndex`、`get`／添字、文字ごとの for、`subSequence`、`substring`。
  長さと添字は UTF-16 code unit に基づく。String／CharSequence の参照・反復に対応し、可変 CharSequence の長さの変更も反復条件に反映する。
- `isEmpty`／`isNotEmpty`／`isBlank`／`isNotBlank`、`first`／`last` と OrNull、
  `take`／`takeLast`／`drop`／`dropLast`、`reversed`／`repeat`／`padStart`／`padEnd`。
- `trim`／`trimStart`／`trimEnd`（文字 vararg を含む）、`trimIndent`／`trimMargin`、
  `removePrefix`／`removeSuffix`／`removeSurrounding`、`uppercase`／`lowercase`。
- `startsWith`／`endsWith`／`contains`、`indexOf`／`lastIndexOf`、
  `substringBefore`／`substringAfter` と Last、`replace`／`replaceFirst`、String／Char delimiter の `split`。
- `equals`／`compareTo` と文字列の順序比較、`toCharArray`／`concatToString`、
  nullable String の `orEmpty`／`isNullOrEmpty`／`isNullOrBlank`／`toString`。
- `toByte`／`toShort`／`toInt`／`toLong`（radix を含む）、`toFloat`／`toDouble` と OrNull、
  `toBoolean`／`toBooleanStrict`／`toBooleanStrictOrNull`。

名前付き引数・既定値・文字列操作の spread は、引数の評価順と配列のコピー時点を維持する。
Unicode の空白・大小文字、split の末尾空要素、空文字の replace は公式 Kotlin と同じ処理を使う。
基本操作にはkswiftk-stdlib.jarを実行時classpathへ追加する。
inline／reified／suspend と組み合わせたテンプレートと、Java／公式 Kotlin からの生成 JAR 利用にも対応する。
Locale 指定 overload と CharSequence のユーザー実装は未対応。Regex と文字列の高階関数は M19 節を参照。

```kotlin
fun main() {
    val name = "  世界  ".trim()
    var greeting = "Hello"; greeting += ", $name"
    println("$greeting: ${"21".toInt() * 2}")
    println("a;b,c".split(';', ','))
    println("A😀界".length)
}
```

## M19: Regex・StringBuilder・文字列の高階関数

Regexは独自stdlibのPattern／Matcher接続、StringBuilderはjava.lang.StringBuilderを使用する。
kswiftk-stdlib.jarを実行時classpathへ追加する。

- Regex の pattern／options、matches／containsMatchIn、find／findAll、matchEntire／matchAt／matchesAt、
  replace（String／transform）／replaceFirst、split／splitToSequence。
  String.toRegex、CharSequence.matches／contains／replace／replaceFirst／split／splitToSequence、
  RegexOption と Regex.escape／escapeReplacement／fromLiteral に対応する。
- MatchResult の value／range／groups／groupValues／destructured／next、数値・名前によるグループ参照、
  MatchGroup の value／range と分解代入、Destructured の component1〜10／toList を扱う。
  range の first／last／start／endInclusive と contains／isEmpty／toString を使用できる。
  findAll の遅延 Sequence は map／filter／toList／count／first／firstOrNull と for 反復に対応する。
- StringBuilder の空・capacity・String・CharSequence constructor、length、添字の取得・代入、
  append／appendLine／appendCodePoint／insert、appendRange／insertRange、deleteAt／deleteRange、
  setRange、clear／reverse／setLength、capacity／ensureCapacity／trimToSize、substring／subSequence、indexOf／lastIndexOf。
  CharArray の専用 overload は内容を追記し、Any? に消去した配列は通常のオブジェクト表現を使う。
  appendRange／insertRange の endIndex は排他的。length は val で、変更には setLength を使う。
  Java 由来の constructor／member は名前付き引数を拒否し、Kotlin 拡張の名前付き引数は許可する。
- String／CharSequence の map／mapIndexed／mapNotNull／mapIndexedNotNull、flatMap／flatMapIndexed（Iterable を返す transform）、
  filter／filterNot／filterIndexed、forEach／forEachIndexed、onEach／onEachIndexed、any／all／none／count、
  fold／foldIndexed／foldRight／foldRightIndexed、reduce 系（Indexed／Right／OrNull）、
  predicate 付き first／last／find／findLast／single と OrNull、indexOfFirst／indexOfLast、
  takeWhile／dropWhile／takeLastWhile／dropLastWhile、toList／toSet、zipWithNext(transform)、
  windowed／chunked（transform あり・なし）、buildString（capacity 指定を含む）。

文字単位の高階関数は UTF-16 code unit を扱う。map／filterNot／fold 等は可変 CharSequence の長さの変更を追従する。
filter／forward reduce／windowed／chunked／zipWithNext 等は取得済みの終端を使う。
String.filter は String、CharSequence.filter は CharSequence（実体は StringBuilder）を返す。
inline API は非ローカル return と suspend 呼び出しを許可し、windowed／chunked／Regex.replace の transform は非 inline として扱う。
公開 inline 関数の生成 JAR を公式 Kotlin から inline 展開することもできる。

```kotlin
fun main() {
    val words = Regex("[a-z]+").findAll("one two").map { it.value.uppercase() }.toList()
    println(words)
    println(buildString { append("lengths="); append("abc".map { it.code }) })
    println("abcde".windowed(3, step = 2, partialWindows = true))
}
```

Regex／StringBuilder／文字列標準関数そのものの関数参照、Regex.toPattern／Pattern.toRegex、
StringBuffer／Appendable の宣言・ユーザー実装は未対応。コレクションと Sequence の追加 API は M20 節を参照。

## M20: コレクション操作・Pair・Sequence

実行時にはkswiftk-stdlib.jarをclasspathに追加する。
Pair は kotlin.Pair を使用し、constructor、to（that という引数名）、first／second、
component1／component2、copy の既定引数、equals／hashCode／toString を扱う。
変数・lambda パラメータでの分解代入と、Java／公式 Kotlin からの Pair 型 API 利用にも対応する。

- Iterable、Array、primitive／unsigned 配列、CharSequence、Sequence の groupBy（valueTransform overload を含む）、
  associate、associateBy（valueTransform overload を含む）、associateWith、partition。
  Map のキーは初出順、重複キーの値は最後の結果を保持し、null キー・値も使用できる。
  String.partition は Pair<String, String>、CharSequence.partition は Pair<CharSequence, CharSequence>（実体は StringBuilder）、
  その他は二つの List の Pair を返す。
- Iterable／Array／primitive・unsigned 配列の zip は相手が Iterable または Array、
  CharSequence.zip は相手が CharSequence、Sequence.zip は相手が Sequence。
  transform あり・なしに対応し、transform なしは infix でも呼び出せる。
  Iterable.zipWithNext は transform あり・なし、文字列の transform 付きは M19 の経路を使う。
- Iterable／Array／primitive・unsigned 配列／Sequence の joinToString。
  separator／prefix／postfix／limit／truncated／nullable transform の名前付き・既定引数に対応する。
  joinToString 自体は非 inline。limit の切り詰めは公式実装と同じ要素数を消費する。
  CharSequence は asSequence().joinToString() を使用する。
- Iterable／Array／primitive・unsigned 配列／CharSequence の asSequence、Iterator.asSequence、
  emptySequence／sequenceOf（spread・名前付き vararg 配列を含む）、generateSequence の三つの overload。
  配列・コレクションからの Sequence は入力の view として反復し、各反復で入力の変更を参照する。
  nextFunction のみの generateSequence と Iterator.asSequence は一度だけ消費できる。
- Sequence の map／mapIndexed／mapNotNull／mapIndexedNotNull、filter／filterNot／filterIndexed／filterNotNull、
  flatMap（Sequence／Iterable）、flatten（Sequence／Iterable）、take／drop／takeWhile／dropWhile、
  distinct／distinctBy、onEach／onEachIndexed、sorted／sortedDescending／sortedBy／sortedByDescending、
  zip／zipWithNext、chunked／windowed、constrainOnce／asIterable。
  これらは遅延評価する。sortedBy の selector は crossinline で、比較ごとに呼び出される。
- Sequence の toList／toMutableList／toSet／toMutableSet／toMap、count／any／all／none、
  first／firstOrNull（predicate あり・なし）、last／lastOrNull／single／singleOrNull、
  elementAt／elementAtOrNull／contains（in／!in を含む）、minOrNull／maxOrNull、
  groupBy／associate 系／partition、forEach／fold。
  predicate を受ける terminal、forEach／fold、groupBy／associate 系／partition は inline として展開する。
- Iterable の toList／toMutableList／toSet／toMutableSet／toMap、take／drop、distinct／reversed、
  sorted／sortedDescending／sortedBy／sortedByDescending、chunked（transform あり・なし）／windowed。
  Iterable／Array／primitive・unsigned 配列の map／filter／forEach／fold は inline source body を使用する。
  listOf／setOf／mapOf と mutable factory の vararg・spread は全引数を評価してから構築し、
  単一引数の overload も公式のものを使用する。

非ローカル return、receiver/captured function value、suspend の遅延再開、公開 inline 関数を使う公式 Kotlin consumer も検証する。
Sequence の map／filter 等の中間 callback と joinToString の transform は非 inline として非ローカル return を拒否する。

```kotlin
fun main() {
    println(listOf("a", "bb", "c").groupBy { it.length })
    println(listOf("a", "bb").associate { it.length to it.uppercase() })
    val (even, odd) = listOf(1, 2, 3).partition { it % 2 == 0 }
    println(even zip odd)
    println(generateSequence(1) { it + 1 }.map { it * 2 }.take(3).joinToString())
}
```

未列挙の Collection／Sequence API（groupingBy／destination 付き To 系／
unzip／plus・minus／sumOf／Comparator を受ける overload 等）、Pair／標準コレクション関数そのものの関数参照、
for ヘッダの分解代入、interface 委譲を使わないユーザーによる Collection の直接実装は未対応。

## M21: Sequence builder

`sequence { ... }` と `iterator { ... }`、SequenceScope の `yield(value)`、
`yieldAll(iterator)`／`yieldAll(elements: Iterable<T>)`／`yieldAll(sequence: Sequence<T>)` に対応する。
kswiftk-stdlib.jarを実行時classpathに追加する。生成物にstdlibは内包しない。

```kotlin
fun main() {
    val values = sequence {
        yield(1)
        yieldAll(listOf(2, 3))
        yieldAll(sequenceOf(4))
        yieldAll(listOf(5).iterator())
    }
    println(values.take(3).toList()) // [1, 2, 3]
    println(values.joinToString()) // 1, 2, 3, 4, 5
}
```

Sequence 作成・iterator 取得では body を実行せず、hasNext／next の要求に応じて中断・再開する。
同じ値を保持する間の hasNext の連続呼び出しでは body を再開しない。
Sequence は反復ごとに新しい coroutine frame を作り、iterator builder は一つの cursor を返す。
外側の可変 capture は共有し、builder 内のローカルは frame ごとに保持する。
有限・無限ループ、break／continue、return@sequence／return@iterator、try／catch／finally、
ネストした builder、nullable・generic・unsigned の要素、suspend receiver 関数値にも対応する。
block の名前付き引数、宣言済みの suspend SequenceScope<T>.() -> Unit を渡す形も使用できる。

builder の body と SequenceScope の suspend extension は、同じ receiver への suspend member／extension
呼び出しに制限する。外部の suspend 関数、別 Scope、this の alias を receiver とした呼び出しは拒否する。
inline lambda からの yield は許可し、非 inline callback からの yield と非ローカル return は拒否する。
型パラメータの上限が SequenceScope である suspend extension も同じ規則を適用する。
関数値の receiver 形式は同一 receiver が必要だが、明示的な引数形式の f(scope) は
通常の suspend 関数からの forwarding も許可する。明示的な f.invoke(scope) は拒否する。
import alias・完全修飾名にも対応し、同名のユーザー関数は通常の宣言として解決する。

`yieldAll`は独自stdlibのScope methodを使用し、空入力の即時復帰と委譲 iterator の遅延消費を保持する。
最後の値の next の直後も body の末尾や finally が未実行の場合があり、さらに hasNext／next を要求すると再開する。
first／take などで途中消費を止めても、残りの body や finally の実行は保証されない。
委譲 iterator 自体の例外は consumer 側で発生し、builder 内の catch／finally を直ちには実行しない。
これらのタイミングは公式 Kotlin と同じである。

生成 JAR の Sequence／Iterator、suspend SequenceScope extension、公開 inline reified builder は
Java／公式 Kotlin consumer でも利用できる。KSwiftK が既に診断している Unit 型引数などの
一般的な JVM 型制限は引き続き適用する。

## M22: 複数ソースと独自 JVM stdlib

```bash
kswiftc --stdlib-only --emit jar -o kswiftk-stdlib.jar
kswiftc main.kt helpers.kt --emit jar --classpath kswiftk-stdlib.jar -o app.jar
java -Xverify:all -cp app.jar:kswiftk-stdlib.jar MainKt
```

`--stdlib-only` は従来どおり既定で Native `.kklib` を生成する。明示的な `--emit jar` で JVM profile を
選び、出力名省略時は `./kswiftk-stdlib.jar` になる。`--emit class` も利用可能。
入力ファイルや `--stdlib-library` との併用は拒否する。

この JAR はmanifestで選んだ共通 Kotlin ソースの Pair／Unit／Function と、
`Stdlib/jvm/kotlin/` 以下の全実装ソースを同時にコンパイルする。
ABI宣言は `Stdlib/jvm/declarations/` に分離し、JDKへの接続は `platform-operations.json` に記述する。
`META-INF/kswiftk-stdlib-sources.list` に採用した resource 相対パスを保存する。
既知APIのsignature照合結果を `META-INF/kswiftk-stdlib-coverage.json` に保存する。ABIの存在は実行網羅率を意味しない。
Native 用 stdlib の source 列挙には JVM platform ソースを含めない。

対応する API は `Pair` の constructor／first／second／component1／component2／copy／copy$default／
equals／hashCode／toString、`to`、print／println、emptyList／emptySet／emptyMap、
listOf／setOf／mapOf と mutableListOf／mutableSetOf／mutableMapOf。
Pair は Serializable を実装し、共通ソースの extension copy も PairKt に出力する。
List／Set／Map の基本参照・size・iteration・membership、可変コレクションの追加・更新・削除は JDK に接続する。
空・単一・vararg overload を分け、集合と map は挿入順、重複キーの最後の値、factory 前の引数評価順を保持する。
vararg listOf は Arrays.asList の配列共有・固定サイズ、singleton set／map は構築時に hashCode を呼ばない挙動を保持する。

公式 Kotlin consumer は暗黙の公式 stdlib を無効にしてコンパイルできる。

```bash
kotlinc -no-stdlib -no-reflect -cp kswiftk-stdlib.jar Consumer.kt -d consumer.jar
java -Xverify:all -cp consumer.jar:kswiftk-stdlib.jar ConsumerKt
javac -cp kswiftk-stdlib.jar JavaConsumer.java
java -Xverify:all -cp .:kswiftk-stdlib.jar JavaConsumer
```

組み込み型の宣言情報は独自生成の `.kotlin_builtins`、ユーザー宣言は facade ごとの `kotlin.Metadata` と
module の package-part index に出力する。公式 JAR の class／resource はコピーしない。
複数入力の全関数・クラスを先に登録し、異なる package 間の呼び出しや top-level property を解決する。
Main-Class は main があるファイルを指し、複数の entry point、同一 package の facade 名重複、
任意の入力ファイルの不正構文・未対応構文は出力を変更する前に拒否する。
source vararg は単独 parameter の通常関数に対応し、Java ACC_VARARGS と Kotlin の element-type metadata、
配列 descriptor／generic signature を出力する。複数parameterのsource varargはstdlibの実装用に受け付ける。通常ユーザーの複数parameter source varargとvararg constructorは未対応。

文字列の検索・trim・置換・数値変換、collectionの基本変換・distinct・take/drop・joinToStringもソースから生成する。
AbstractSet のユーザー派生クラスは size と iterator を実装でき、Set の等値比較・hashCode・
Collection ABI と readonly marker を継承する。size property は getSize() と JVM size() bridge を使う。
詳細な実装範囲と検証方法は [JVM stdlib のソース化](jvm-stdlib.md) を参照。

このprofileは対応済みのRegex／Sequence／Sequence builder／coroutine／reflection、unsigned runtimeと高階collection APIを含む。これらの実行に公式stdlib／reflect JARは不要。
静的なKotlin参照閉包は`python3 Scripts/validate_jvm_stdlib.py kswiftk-stdlib.jar app.jar`で検査する。

## 未対応と診断

外部 field／property、
明示的な backing field 宣言、
main の配列引数、複数上限の where 制約、
拡張プロパティ、ローカル関数、
複数 parameter のユーザー定義 vararg と vararg constructor（単独 vararg 関数・対応済み API の spread は使用可能）、
enum の secondary constructor、when の guard／範囲条件、ループラベル、`until` / `step` は未対応。
Unit 型の通常のパラメータ宣言／型引数／配列要素（Any? 引数へ渡す Unit 式、関数型の戻り値、Continuation／Result の型引数と resume(Unit) を除く）、AbstractSet 派生以外の collection のユーザー実装、kotlin.Number のユーザー派生クラス、
上記以外の高階 collection 操作・builder、data class／Pair／MatchGroup／MatchResult.Destructured 以外や for ヘッダでの destructuring は未対応。
関数型は context receiver なし、receiver を含め22引数まで（suspend 関数型は Continuation 分を除き21引数まで）。
対応範囲外の構文・型は `KSWIFTK-JVM-0001`、共有の意味解析エラーは既存の Sema 診断で拒否する。
いずれも既存出力を書き換えない。

Native ライブラリ／非ホスト target triple、カスタム entry point、incremental、
`-O1` 以上、`-g`、feature flag も拒否する（`time-phases` と `no-incremental` は使用可能）。
関数の非nullableな `Nothing` 戻り値は `java.lang.Void` のJVM descriptorとKotlin metadataで保持する。
通常の戻り先は専用の `KotlinNothingValueException` で終端する。own-JAR は同例外の引数なし、String?、String?／Throwable?、Throwable? の4コンストラクタを提供する。
`Nothing?` の公開戻り値、関数・コンストラクタの `Nothing`／`Nothing?` 引数とreceiver、
プロパティの `Nothing`／`Nothing?` 型は使用できない。null式とローカルの `Nothing?` はObject表現を使う。
Java 8 が扱えない private interface メンバーも診断して拒否する。null だけを返す関数には
`String?` など対応する戻り型を明示する。Maven／Gradle の依存解決、JAR Manifest の
Class-Path、multi-release JAR のバージョン選択、JRT／module path は扱わない。
classpath の読み込み失敗は `KSWIFTK-JVM-0003` で診断する。

## 実装境界

```text
LoadSources → JVMPreparation → Lex → Parse → BuildAST
  → JVMSourceValidation → Sema → JVMFrontend → JVMCodegen
```

Lexer／Parser／AST／Sema を Native 経路と共有する。`JVMPreparationPhase` が JVM 用の
console 宣言と classpath の宣言 stub を仮想ソースとして追加する。
`JVMClassReader` は classfile の公開 signature を読み、`JVMClasspathIndex` が共有 Sema の
header 収集後・override 検査前に外部 SymbolID と実際の JVM owner／descriptor を対応付ける。
依存コードや static initializer はコンパイル時には実行しない。Native bundled stdlib の準備は通らない。
AST 構築で省略される構文があるため、`JVMSourceValidationPhase` がソースの対応文法も検査する。

`JVMProgramBuilder` は解決済みの型・関数から `JVMProgram` の型付き IR を構築する。
各値は型と固定ローカルスロットを持ち、分岐の operand stack は空に保つ。
変数の読み出しを snapshot してから次の引数・オペランドを評価するため、
`f(x, x++)` のような式でも左から右の評価順と以前の値を保持する。
可変ローカルは1要素配列のセルへ格納する。ラムダの本体を同じ owner 内の synthetic static
メソッドへ出力し、別の synthetic class が capture を保持して FunctionN.invoke から本体を呼ぶ。
Native 用の KIR／Lowering／ABI は通らない。

`JVMClassFile` は facade の static メソッドと必要な launcher、各 class／interface の
継承関係・field・instance method・accessor・constructor・bridge を生成する。
抽象メソッドには Code 属性を付けず、constructor の初期化前 this は専用の検証型で追跡する。
Signature 属性はクラスの superclass を先頭にし、interface と型引数を後に記録する。
各メソッドの scratch locals を冒頭で既定値に初期化し、全分岐先へ固定型の full
`StackMapTable` frame を出力する。これは JVM verifier のための初期化であり、ソースでの
初期化前の読み出しを許可する機能ではなく、ソースの definite assignment は Sema が検証する。条件分岐は反転した短距離 test と `goto_w` を組み合わせ、
大きなメソッドでも分岐 offset を切り詰めない。
コンストラクタの `new` は引数より前に評価し、初期化前の参照は allocation offset とともに
frame に記録する。引数から break／continue する辺では未完了の allocation slot を null に戻す。256 以上のローカルスロットには `wide` を使う。
公開 inline entry の constructor は外部 Kotlin inliner が解釈できる NEW／DUP／invokespecial 形式にする。
引数の評価前には Class.forName による初期化を行い、JVM class initializer の実行順を保持する。

文字列定数は modified UTF-8、Long／Double 定数は constant pool の 2 slot を使用する。
定数長、constant pool、method code 長の上限超過は `KSWIFTK-JVM-0002` で診断する。
`JVMJarArchive` は固定タイムスタンプの非圧縮 ZIP を生成する。同じ入力の JAR は
同じバイト列になる。classfile／JAR の全バイトを構築してから出力を atomic に置換する。

## 検証

JDK と公式 `kotlinc`（検証基準 2.4.20）を PATH に配置して次を実行する。

```bash
bash Scripts/swift_test.sh --no-parallel --filter JVMBackendTests
bash Scripts/swift_test.sh --no-parallel --filter CLIParserTests
```

`JVMBackendTests` と M2〜M22 の拡張は、`.class`／`.jar` を `java -Xverify:all` で実行する。
M1 に加え、型付き変数、再帰／オーバーロード、shadowing、全経路 return、数値変換・overflow・
NaN、短絡評価・increment の評価順、各種ループ・範囲境界、大きな分岐と wide locals を検証する。
不正な型・スコープ・再代入・未対応構文の拒否も固定する。

M3 は javac で作る依存 JAR／class ディレクトリ、コンストラクタの初期化順と CFG、
static／instance／interface 呼び出し、継承、null／boxing、Java・公式 Kotlin の consumer、
Kotlin 製 JAR の import、internal／private の拒否、classpath 異常時の出力保護を検証する。

M4 は複数 classfile の実行、constructor chain と初期化順、custom accessor、private／protected、
abstract class、動的ディスパッチ、共変 override の bridge、継承 default method の super 呼び出し、
Java／公式 Kotlin のクラス consumer と可視性を検証する。代表的な M4 プログラムは公式 kotlinc
の実行結果とも比較する。

M5 は generic class／function／interface と boxing bridge、配列と collection の変更・反復、
nullable primitive、Java／公式 Kotlin consumer の型検査、外部 Java の配列 signature、
throw／catch／finally の値と例外の伝播を検証する。finally の字句スコープ・ループ、
戻り値／例外の置換、pending constructor と superclass constructor 引数の handler frame も
公式 Kotlin の実行結果と比較する。

M6 は可変 capture、receiver、関数型プロパティ、配列／collection の callback、
Java／公式 Kotlin の関数 ABI を検証する。M7 は source／Java SAM、inline の実展開と非局所 return、
suspend main／generic bridge、複数回の中断と再開、ループの Long ローカル、再開時の例外と finally、
suspend SAM と Unit、別パッケージの Java／公式 Kotlin consumer を検証する。
coroutine テストでは公式 kotlinc の参照 JAR を runtime として併用し、生成物を classpath の先頭にして
参照側の同名 facade による偽陽性を防ぐ。consumer は stdlib と生成物の両 classpath 順で実行する。
M8 は singleton／companion の初期化順と private access、data の生成メソッド・copy の default mask、
enum の定数本体・抽象 property・空の enum、sealed／nested class と when、Java／公式 Kotlin consumer、
未対応構文での既存出力保護を検証する。

M9 は匿名 object の capture／初期化／generic supertype、inner の outer chain と generic parameter、
data object の生成メソッドと継承、名前付き引数の評価順、既定式の例外と nullable／wide value、
複数 mask、object／enum の super 引数、inline default lambda、suspend default ABI を検証する。
共有 Sema は匿名型の公開範囲と名前付きの配列 size／init も検査し、Native の配列 lowering も評価順を保持する。
Java／公式 Kotlin consumer は inner constructor と default bridge を実際に呼び、classpath の両順で実行する。

M10 は class 委譲の override／default／generic bridge・初期化順、delegate の get／set／provide と
extension operator、mutable token・private static field、標準 Delegates、lazy の cache／nullable／retry、
lateinit の例外型・message・isInitialized と capture を、class／JAR の両方で公式 Kotlin と比較する。
Java／公式 Kotlin consumer は両 classpath 順で実行し、Java の並列呼び出しで既定 lazy の一度限りの初期化も検査する。

M11 は value class の primitive／reference／nullable／wide ABI、boxing と init、interface／abstract dispatch、
default、名前修飾後の callable reference とクラス初期化、generic alias、annotation の定数・配列・KClass・
retention／use-site／property carrier を検証する。Java／公式 Kotlin consumer は生成 JAR の metadata、
value constructor／helper、annotation reflection と const field を呼ぶ。実行は `java -Xverify:all` を使用し、
参照コンパイルの user class が生成物の不足を補わないよう、公式 runtime JAR と参照 JAR を分ける。

M12 は generic value class の上限／nullable／boxing／capture と generic Signature、repeatable の
自動／明示 container、retention、use-site、クラス／関数／parameter／property の展開を検証する。
Java／公式 Kotlin consumer が生成 JAR を呼び、Java consumer の generic reflection も検査する。
公式 Kotlin との比較では runtime と参照 user class を別 classpath に保ち、生成物を `java -Xverify:all` で実行する。

M13 は配列の equality／hash／表示、入れ子の nullable／generic storage と getter、primary／secondary の
既定値・委譲・初期化順・例外・wide 引数・複数 mask・capture を class／JAR で公式 Kotlin と比較する。
Java／公式 Kotlin consumer では、default factory、constructor reflection、field と method の generic Signature を検査する。

M14 は inline の callback／non-local return／finally、primitive・wide・reference・generic・nullable の
suspend return、default bridge、interface／value member、関数参照、遅延 resume と例外を検証する。
別 package の公式 Kotlin consumer と Java consumer は生成 JAR を使い、同期 return と resume の型も検査する。

M15 は reified の nullable 判定・cast・class literal・配列・型引数転送と escaping lambda を、
.class／JAR の両方で公式 Kotlin の結果と比較する。別 package の公式 Kotlin consumer は
生成 JAR の inline suspend／reified を展開し、既定引数・finally・value class・遅延 resume を実行する。
Java consumer は通常 entry の同期復帰と遅延 resume を検査し、全生成物を java -Xverify:all で実行する。

M16は専門化された関数参照のbound／unbound receiver・型引数転送・既定引数・Unit／suspend adapter・
reflection・SAM・value classと、匿名objectのinitializer／getter／nested capture／mutable cellを検証する。
.class／JARを公式Kotlinと比較し、別packageの公式Kotlin consumerとJava consumerでも生成JARを実行する。
匿名object内のlazy lambdaが直接T::classを使うケースは、公式Kotlin 2.4.20側に未解決markerが残るため、
候補の期待値を独立したテストで固定している。その他のM16ケースは公式Kotlinとの結果比較を維持する。

M17はCharのUTF-16値、Byte／Shortの昇格・切り詰め、unsigned境界値・比較・除算・浮動小数点変換・bit演算、
primitive配列・nullable・generic／collection・capture・value class・annotationを.class／JARで実行し、公式Kotlinと比較する。
Java／公式Kotlin consumerは生成JARのdescriptor・名修飾・constructor・inline／suspendの同期／遅延復帰を検査する。
nullable unsigned配列のerased transportとnull assertion、型範囲外のliteral／signature clashでの既存出力保護も検証する。

M18 は連結／テンプレートの評価・文字列化の順序、Unit／null／配列／unsigned、
UTF-16・raw／multi-dollar・Unicode 空白／大小文字、検索／置換／split／数値変換と失敗を検証する。
String の各種 +=、副作用付き spread／名前付き引数、throw／return、capture／遅延 suspend 復帰も、
.class／JAR を公式 Kotlin と比較する。Java／公式 Kotlin consumer は生成 JAR の inline／reified／
suspend と可変 CharSequence の反復を実行し、不正な文字列操作では既存出力が保護されることを確認する。

M19 は Regex の名前付き・未一致グループ、ゼロ幅一致・UTF-16 境界、遅延 Sequence、置換と split の既定引数、
StringBuilder の配列 overload・範囲・例外、文字列高階関数の可変レシーバ・終端取得、
非ローカル return／finally／遅延 suspend 復帰と、Java／公式 Kotlin consumer を比較する。
非 inline callback の return、Java API の named argument、不正な null と既存出力の保持も確認する。

M20 は group/associate の順序・重複・null、Pair の ABI・copy・分解代入、zip の消費数、
joinToString の既定値・評価順・limit、Sequence の遅延性・再反復・一回消費制約を公式 Kotlin と比較する。
primitive／unsigned 配列、Float／Double の NaN、spread と singleton factory の hashCode、
inline return／suspend と Java／公式 Kotlin consumer、不正入力時の出力保持も確認する。

M21 は builder 作成・iterator 取得・hasNext／next ごとの遅延評価、yieldAll の三 overload、
空入力・無限入力の部分消費、再反復と capture、例外・finally と失敗後の iterator を比較する。
公開 suspend extension／inline reified builder の Java・公式 Kotlin consumer と、
restricted suspension・不正な型／引数／return による既存出力の保持も確認する。

M22 は共通 Pair source と JVM platform の複数ソースから stdlib を二度生成して byte 一致を検証し、
独自 JAR のみを classpath に置いた Hello World・Pair・空／単一／vararg collection・可変操作・spread／名前付き配列・反復を確認する。
Java consumer は共通 extension copy、vararg ABI、配列共有、singleton の hash 評価を検証する。
公式 Kotlin consumer は `-no-stdlib -no-reflect` で compile／実行し、Map 代入・membership、cast、
nullable Float／Double equality と runtime Metadata も検証する。独自 builtins resources を除いた negative control は失敗を要求する。
複数 package の相互参照、property、class、closure、primitive／generic／配列要素／receiver／member vararg、
後続ファイルの不正構文、facade 衝突と複数 main の出力保持、Native bundle への JVM source 混入防止も対象とする。

JVMStdlibCatalogTestsは宣言と実装の選択、ThisTemplateParsingTestsは `$this` のASTを検証する。
JVMBackendTestsのstdlibSourceRuntimeStringsAndCollectionsは独自JARだけで文字列・collectionを実行し、
公式Kotlin consumerにも同じclasspathを使って参照出力と比較する。

独自runtimeの回帰は`repositoryStdlibRuntimeRegression`で、既存M4〜M21の実行例と境界ケースをclass／JARの双方で生成し、生成物と独自stdlibだけのclasspathを検査する。
`officialKotlinConsumerUsesOnlyRepositoryStdlib`は公式Kotlinが生成したSequence builder・Regex・suspend・lazy・reflectionのconsumerを独自JARだけで実行する。
`ownStdlibLazyConcurrencyAndJavaConsumer`は指定monitor、SYNCHRONIZED、PUBLICATION、例外後の再試行、null保持をJava consumerから検査する。
