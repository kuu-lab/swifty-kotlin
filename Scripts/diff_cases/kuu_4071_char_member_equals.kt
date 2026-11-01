// DIFF_JVM
// KUU-4071: member equals(other: Any?) on a Char receiver must box through the
// wrapper type instead of failing with "Unsupported JVM member: equals".
fun main() {
    println('a'.equals('b'))
    println('a'.equals('a'))
    val c: Char = 'x'
    println(c.equals('x'))
    println(c.equals('y'))
    println(c.equals("x"))
    println(c.equals(null))
    println(c.equals(120))

    val nc: Char? = 'x'
    println(nc?.equals('x'))
    println(nc?.equals('y'))
    val missing: Char? = null
    println(missing?.equals('x'))

    println(1.equals(1))
    println(1.equals(1L))
    println(1L.equals(1L))
    println(true.equals(true))
    println(true.equals(1))
    println(1.5.equals(1.5))
    println(1.5f.equals(1.5f))
    println(Double.NaN.equals(Double.NaN))
    println((-0.0).equals(0.0))
    println(1u.equals(1u))
    println(1u.equals(1))
    println(127.toByte().equals(127.toByte()))
    println(1.toShort().equals(1.toShort()))
    println('a'.equals(97))
}
