// Regression: invoking a `context(A, B) () -> T` function value must supply
// every implicit context argument from the receiver tower, not just the
// innermost `with` receiver (KUU-3897). Before the fix the outer String
// context argument was dropped, producing an arity-mismatched
// kk_function_invoke_2 call (panic, or null via the absent-key sentinel).
fun <T> withTwo(v: String, n: Int, f: context(String, Int) () -> T): T =
    with(v) { with(n) { f() } }

fun <T> withSwapped(n: Int, v: String, f: context(Int, String) () -> T): T =
    with(v) { with(n) { f() } }

fun main() {
    // Anonymous context function passed as a contextual-function-typed arg.
    println(withTwo("x", 7, context(a: String, n: Int) fun(): String { return "$a$n" }))
    // Bound to a val, then invoked inside nested `with` scopes.
    val g: context(String, Int) () -> String = context(a: String, n: Int) fun(): String { return "$a$n" }
    with("y") { with(8) { println(g()) } }
    // Context receiver order follows the function type, not the tower.
    println(withSwapped(3, "z", context(n: Int, a: String) fun(): String { return "$a$n" }))
    // A single context receiver still resolves to the innermost match.
    val h: context(Int) () -> String = context(n: Int) fun(): String { return "s$n" }
    with("w") { with(4) { println(h()) } }
    // Invoking through a nested lambda must forward the outer `with`
    // receiver through each middle lambda's captures — the inline forEach
    // body and a local lambda both count (KUU-3897).
    val k: context(String, Int) () -> String = context(a: String, n: Int) fun(): String { return "$a$n" }
    with("x") { with(7) { listOf(1, 2).forEach { println(k()) } } }
    with("x") { with(7) { val l = { k() }; println(l()) } }
    // Three context slots of distinct types each reach their receiver.
    val m: context(String, Int, Boolean) () -> String = context(a: String, n: Int, b: Boolean) fun(): String { return "$a$n$b" }
    with("x") { with(7) { with(true) { println(m()) } } }
}
