import kotlin.reflect.typeOf

fun add(a: Int, b: Int): Int = a + b

fun takeFn(f: Function2<Int, Int, Int>): Int = f(1, 2)

fun main() {
    // KType.toString renders function types in Kotlin notation.
    println(typeOf<() -> Unit>())
    println(typeOf<(() -> Unit)?>())
    println(typeOf<(Int) -> String>())
    println(typeOf<Int.() -> String>())
    println(typeOf<(() -> Unit) -> Int>())
    println(typeOf<(Int) -> () -> Unit>())
    println(typeOf<(Int, Int) -> Int>())
    println(typeOf<List<() -> Unit>>())

    // The nominal FunctionN form normalizes to the same notation.
    println(typeOf<Function1<Int, String>>())
    println(typeOf<Function2<Int, String, Long>>())
    println(typeOf<Function1<in Int, out String>>())

    // arguments covers the parameter types plus the return type.
    println(typeOf<() -> Unit>().arguments.size)
    println(typeOf<(Int, Int) -> Int>().arguments.size)
    println(typeOf<(Int, Int) -> Int>().arguments[0])
    println(typeOf<(Int, Int) -> Int>().arguments[2])
    println(typeOf<() -> Unit>().arguments[0])

    // Different function types are not equal; identical ones are.
    println(typeOf<() -> Int>() == typeOf<() -> Unit>())
    println(typeOf<() -> Unit>() == typeOf<() -> Unit>())
    println(typeOf<(Int) -> Int>() == typeOf<(Int, Int) -> Int>())

    // typeOf<FunctionN<...>> equals typeOf of the same function type.
    println(typeOf<Function1<Int, String>>() == typeOf<(Int) -> String>())
    println(typeOf<() -> Unit>().classifier == Function0::class)

    // FunctionN nominal types are usable as declarations and parameters.
    val f: Function1<Int, String> = { x: Int -> x.toString() }
    println(f(5))
    println(takeFn(::add))

    // `is` checks on boxed (capturing) lambdas test the arity.
    val cap = 0
    val l1: (Int) -> Int = { it + cap }
    println(l1 is Function1<*, *>)
    println(l1 is Function2<*, *, *>)
    val anyFn: Function1<Int, String> = l1.let { { x: Int -> (x + cap).toString() } }
    println(anyFn is Function1<*, *>)
    val s: Any = "x"
    println(s is Function1<*, *>)
    println(s as? Function1<*, *> == null)
}
