@file:OptIn(ExperimentalContracts::class)
import kotlin.contracts.*

fun present(x: String?): Boolean {
    contract { returns(true) implies (x != null) }
    return x != null
}
fun absent(x: String?): Boolean {
    contract { returns(false) implies (x != null) }
    return x == null
}
fun result(x: String?): String? {
    contract { returnsNotNull() implies (x != null) }
    return x
}
fun both(a: String?, b: String?): Boolean {
    contract {
        returns(true) implies (a != null)
        returns(true) implies (b != null)
    }
    return a != null && b != null
}
fun runIt(tag: Int, f: () -> Int): Int {
    contract { callsInPlace(f, InvocationKind.EXACTLY_ONCE) }
    return f() + tag
}
fun twice(f: () -> Unit) {
    contract { callsInPlace(f, InvocationKind.AT_LEAST_ONCE) }
    f()
    f()
}
fun probe(a: String?, b: String?) {
    if (present(a)) println(a.length)
    if (!absent(a)) println(a.length)
    if (absent(a)) println("null") else println(a.length)
    if (result(a) != null) println(a.length)
    if (null == result(a)) println("null") else println(a.length)
    if (present(a) == true) println(a.length)
    if (present(a) && a.length > 0) println(a.length)
    if (both(b = b, a = a)) println(a.length + b.length)
}
fun main() {
    probe("abc", "de")
    probe(null, "de")
    val d: Int
    println(runIt(f = { d = 5; d }, tag = 0))
    println(d)
    val text: String
    runIt(0) { text = "shared"; text.length }
    println(text)
    var repeated: Int
    twice { repeated = 7 }
    println(repeated)
}
