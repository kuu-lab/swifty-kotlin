// STDLIB-HOF-029: 関数型完全実装テストケース

// 基本的な関数型の使用
fun testBasicFunctionTypes() {
    // Function0-22 の基本テスト
    val f0: () -> Int = { 42 }
    val f1: (String) -> Int = { it.length }
    val f2: (Int, String) -> String = { num, str -> "$num-$str" }
    
    println(f0())
    println(f1("hello"))
    println(f2(123, "test"))
}

// 関数型の変位指定テスト
fun testFunctionVariance() {
    // 共変性（out）のテスト
    val stringProducer: () -> String = { "hello" }
    val anyProducer: () -> Any = stringProducer // OK: StringはAnyのサブタイプ
    
    // 反変性（in）のテスト  
    val anyConsumer: (Any) -> Unit = { println(it) }
    val stringConsumer: (String) -> Unit = anyConsumer // OK: AnyはStringのスーパータイプ
    
    println(anyProducer())
    stringConsumer("test")
}

// 関数型の合成テスト。andThen/compose は kotlin-stdlib に存在しないため
// （java.util.function.Function 由来であり kotlin.Function1 は継承しない）、
// 関数型レシーバを持つ拡張関数として自分で定義する。BUG-C（拡張関数の
// レシーバが関数型自体になれない不具合）修正により有効化。
fun <A, B, C> ((A) -> B).andThen(g: (B) -> C): (A) -> C = { x -> g(this(x)) }
fun <A, B, C> ((A) -> B).compose(g: (C) -> A): (C) -> B = { x -> this(g(x)) }

fun testFunctionComposition() {
    val double: (Int) -> Int = { it * 2 }
    val toStringFn: (Int) -> String = { it.toString() }

    // andThen: f.andThen(g) = { x -> g(f(x)) }
    val doubleThenToString = double.andThen(toStringFn)
    println(doubleThenToString(5)) // "10"

    // compose: f.compose(g) = { x -> f(g(x)) }
    val lengthThenDouble = double.compose { s: String -> s.length }
    println(lengthThenDouble("abc")) // 6
}

// 関数型のカリー化テスト - 一時的にコメントアウト（拡張関数が未実装のため）
/*
fun testFunctionCurrying() {
    val add: (Int, Int) -> Int = { a, b -> a + b }
    
    // カリー化: (Int, Int) -> Int -> Int -> (Int -> Int)
    val curriedAdd = add.curried()
    val add5 = curriedAdd(5)
    println(add5(3)) // 8
    
    // 部分適用のテスト
    val multiply: (Int, Int) -> Int = { a, b -> a * b }
    val curriedMultiply = multiply.curried()
    val double = curriedMultiply(2)
    println(double(7)) // 14
}
*/

// suspend関数型のテスト
/*
import kotlinx.coroutines.*
suspend fun testSuspendFunctionTypes() {
    val suspendFunction: suspend (Int) -> String = { delay(100); "Result: $it" }
    val result = suspendFunction(42)
    println(result)
}
*/

// 高階関数での関数型使用
fun testHigherOrderFunctions() {
    val numbers = listOf(1, 2, 3, 4, 5)
    
    // Function1の使用
    val mapper: (Int) -> String = { "Number: $it" }
    val mapped = numbers.map(mapper)
    println(mapped)
    
    // Function2の使用
    val comparator: (Int, Int) -> Int = { a, b -> a - b }
    val sorted = numbers.sortedWith(comparator)
    println(sorted)
}

// 関数型のネストと複雑な型
fun testComplexFunctionTypes() {
    // 関数を返す関数
    val functionFactory: (Int) -> (String) -> Boolean = { multiplier ->
        { str -> str.length * multiplier > 10 }
    }
    
    val validator = functionFactory(2)
    println(validator("hello")) // false
    println(validator("hi")) // false
    
    // 関数を引数に取る関数
    val applyTwice: ((Int) -> Int, Int) -> Int = { f, x -> f(f(x)) }
    val increment: (Int) -> Int = { it + 1 }
    println(applyTwice(increment, 5)) // 7
}

fun main() {
    testBasicFunctionTypes()
    testFunctionVariance()
    testFunctionComposition()
    // testFunctionCurrying() // 一時的にコメントアウト（curried() は kotlin-stdlib に存在せず、多変数関数型の拡張実装は本PRの対象外）
    testHigherOrderFunctions()
    testComplexFunctionTypes()
    
    // suspend関数のテストはコメントアウト（コルーチン環境が必要）
    // runBlocking { testSuspendFunctionTypes() }
}
