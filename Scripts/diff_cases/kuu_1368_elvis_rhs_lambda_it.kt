// KUU-1368: an Elvis `?:` RHS lambda binds its implicit `it` parameter from
// the LHS's non-null function type, matching kotlinc.

fun f(g: ((String) -> Int)?) = g ?: { it.length }

// kotlinx-cli ArgType.Choice shape: `it` inside the `find` predicate is the
// outer Elvis-RHS lambda's String parameter (the inner lambda declares `e`
// explicitly), and the nested `?: throw` Elvis narrows the `T?` result.
fun <T> pick(toVariant: ((String) -> T)?, toString: (T) -> String, values: List<T>): (String) -> T {
    return toVariant ?: {
        values.find { e -> toString(e).equals(it, ignoreCase = true) }
            ?: throw IllegalArgumentException("No enum constant $it")
    }
}

fun main() {
    val g: ((String) -> Int)? = null
    println(f(g)("hello"))
    println(f { it.length * 2 }("hi"))

    val pickFn = pick<String>(null, { s -> s }, listOf("a", "b"))
    println(pickFn("B"))
    try {
        pickFn("q")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    // The LHS seed also narrows the RHS literal: `b ?: 0` types as Byte.
    val b: Byte? = null
    val z: Byte = b ?: 0
    println(z)
}
