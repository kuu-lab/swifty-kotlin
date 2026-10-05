import kotlin.reflect.typeOf

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

    // `as?` on a non-function value still yields null.
    val s: Any = "x"
    println(s as? Function1<*, *> == null)
}
