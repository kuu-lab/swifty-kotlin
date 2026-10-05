import kotlin.contracts.*

@OptIn(ExperimentalContracts::class)
fun isStr(x: Any?): Boolean {
    contract { returns(true) implies (x is String) }
    return x is String
}

@OptIn(ExperimentalContracts::class)
fun notStr(x: Any?): Boolean {
    contract { returns(false) implies (x is String) }
    return x !is String
}

fun f(x: Any?) {
    if (isStr(x)) println(x.length)
    if (!notStr(x)) println(x.length)
}

fun main() {
    f("hello")
    f(42)
    f(null)
}
