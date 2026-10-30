// KUU-3824 / KT-83308: a `fun interface` whose only abstract member is a
// declared `Any.toString` gets a SAM wrapper that must also answer the
// erased-Any toString dispatch (`kk_any_to_string`), not only the interface
// itable slot.

fun interface SomeFun {
    override fun toString(): String
}

fun foo(o: Any) = o.toString()

fun main() {
    // Lambda-literal SAM conversion (JetBrains samWithAbstractToString2).
    val o = SomeFun { "O" }
    val k = SomeFun { "K" }
    println(o.toString() + foo(k))

    // Function-value SAM conversion (JetBrains samWithAbstractToString3).
    val oLambda: () -> String = { "O2" }
    val kLambda: () -> String = { "K2" }
    val o2 = SomeFun(oLambda)
    val k2 = SomeFun(kLambda)
    println(o2.toString() + foo(k2))

    // Other erased-Any renderings share the same per-object override table.
    val any: Any = SomeFun { "S" }
    println("$any")
    println(any)
    println(listOf(SomeFun { "L" }))
}
