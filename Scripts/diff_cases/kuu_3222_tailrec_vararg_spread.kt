// KUU-3222: a tailrec function taking a function-type parameter is
// auto-inlined, and the inline pass resolved every `fn(...)` invoke to the
// lambda passed at the first call. Tailrec lowering rebinds the parameter
// slot on every loop iteration, so the base case must dispatch to the lambda
// built during the final iteration — not the stale initial one.
tailrec fun <T> collect(vararg items: String, fn: (String) -> T): T = when (items.size) {
    0 -> fn("")
    else -> collect(*items.drop(1).toTypedArray()) { s -> fn(items.first() + s) }
}

tailrec fun firstOnly(vararg items: String, fn: (String) -> String): String = when (items.size) {
    0 -> fn("")
    else -> firstOnly(*items.drop(1).toTypedArray()) { fn(items.first()) }
}

tailrec fun nest(n: Int, fn: (String) -> String): String {
    if (n == 0) {
        return fn("")
    }
    return nest(n - 1) { s -> fn("x" + s) }
}

fun main() {
    println(collect("a", "b", "c", "d", "e") { it })
    println(firstOnly("a", "b", "c") { "seed:" + it })
    println(nest(3) { "base:" + it })
}
