// KUU-3098: unary `+` forwarded its operand's KIR id verbatim. When the
// operand was a bare local read, the result aliased that local's storage
// register instead of a value snapshot, so later writes through either name
// retroactively changed the other side: `val a = +b` initializers, binary
// lhs evaluated before a mutating rhs (`+b + b++`), and `return +b` before a
// mutating `finally` all observed the wrong value.
fun combine(a: Int, b: Int): String = "$a,$b"

fun returnBeforeFinally(): Int {
    var n = 10
    try {
        return +n
    } finally {
        n = 20
    }
}

fun main() {
    var n = 10
    val saved = +n
    n = 20
    println(saved)

    n = 10
    println(+n + n++)

    println(returnBeforeFinally())

    val m = 10
    var mutableSaved = +m
    mutableSaved = 20
    println(m)

    var p = 10
    println(combine(+p, p++))
}
