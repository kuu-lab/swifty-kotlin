package golden.sema

// STDLIB-COMP-FN-007: maxOf — Comparable version (2-arg, 3-arg, vararg)

fun maxOf2ArgString(a: String, b: String): String = maxOf(a, b)
fun maxOf3ArgString(a: String, b: String, c: String): String = maxOf(a, b, c)
fun maxOfVarargString(): String = maxOf("d", "b", "a", "c")
