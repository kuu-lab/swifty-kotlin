// JetBrains kt9532: `"1234$a"` where `a` is a `const val` is a compile-time
// constant on the JVM — folded into one interned literal, so the non-const
// initializers in A and B must share the same instance (KUU-3180).
object A {
    const val a: String = "$"
    const val b = "1234$a"
    const val c = 10000

    val bNonConst = "1234$a"
    val bNullable: String? = "1234$a"
}

object B {
    const val a: String = "$"
    const val b = "1234$a"
    const val c = 10000

    val bNonConst = "1234$a"
    val bNullable: String? = "1234$a"
}

fun main() {
    if (A.a !== B.a) { println("Fail 1"); return }
    if (A.b !== B.b) { println("Fail 2"); return }
    if (A.c !== B.c) { println("Fail 3"); return }
    if (A.bNonConst !== B.bNonConst) { println("Fail 4"); return }
    if (A.bNullable !== B.bNullable) { println("Fail 5"); return }
    println("OK")
}
