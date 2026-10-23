// KUU-2937: primitive member calls on values smartcast to primitives via
// `is`/`!is` on `Any` must operate on the unboxed value, not the box handle.
// Adapted from JetBrains intrinsics/charToInt.kt.
fun main() {
    val x: Any = 'A'
    var y = 0
    if (x is Char) { y = x.toInt() }
    println(y)

    val l: Any = 99L
    if (l is Long) { println(l.toInt()) }
    if (l is Long) { println(l + 1) }

    val d: Any = 1.5
    if (d is Double) { println(d.toInt()) }
    if (d is Double) { println(d + 0.5) }

    val i: Any = 42
    if (i is Int) { println(i.toLong()) }
    if (i is Int) { println(i.inv()) }

    val b: Any = 5.toByte()
    if (b is Byte) { println(b.toInt()) }

    val s: Any = 6.toShort()
    if (s is Short) { println(s.toInt()) }
}
