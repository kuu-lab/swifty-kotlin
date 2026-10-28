// KUU-3537: kotlin.Cloneable and Array.clone() parity — on the JVM every
// array type implements java.lang.Cloneable, so `is`/`as` checks and the
// clone() extensions must agree on both compilers. Unsigned arrays are
// value classes on the JVM and are deliberately excluded.

fun main() {
    val a = intArrayOf(1, 2, 3)
    val b: Cloneable = a as Cloneable
    println(a is Cloneable)
    println(b is Cloneable)

    // Runtime check through Any erasure.
    val anyA: Any = a
    println(anyA is Cloneable)

    val g = arrayOf("x", "y")
    println(g is Cloneable)
    val anyG: Any = g
    println(anyG is Cloneable)

    // A non-array value must not match.
    val notArray: Any = 7
    println(notArray is Cloneable)

    // clone() produces an independent copy with equal contents.
    val copy = a.clone()
    println(copy.contentToString())
    println(copy.contentEquals(a))
    copy[0] = 9
    println(a.contentToString())

    val gCopy = g.clone()
    println(gCopy.contentToString())
    println(gCopy.contentEquals(g))
}
