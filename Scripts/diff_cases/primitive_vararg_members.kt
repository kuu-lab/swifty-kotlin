// KUU-1269: primitive varargs must retain array storage and resolve contains.
// KUU-1281: non-empty asList value boxing is tracked separately; check its size.
fun probeBoolean(vararg xs: Boolean) {
    println(xs.contains(true))
    println(xs.contains(false))
    println(true in xs)
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeByte(vararg xs: Byte) {
    println(xs.contains(1.toByte()))
    println(xs.contains(2.toByte()))
    println(1.toByte() in xs)
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeChar(vararg xs: Char) {
    println(xs.contains('a'))
    println(xs.contains('b'))
    println('a' in xs)
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeDouble(vararg xs: Double) {
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeFloat(vararg xs: Float) {
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeInt(vararg xs: Int) {
    println(xs.contains(1))
    println(xs.contains(2))
    println(1 in xs)
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeLong(vararg xs: Long) {
    println(xs.contains(1L))
    println(xs.contains(2L))
    println(1L in xs)
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun probeShort(vararg xs: Short) {
    println(xs.contains(1.toShort()))
    println(xs.contains(2.toShort()))
    println(1.toShort() in xs)
    println(xs.toList())
    if (xs.isEmpty()) println(xs.asList()) else println(xs.asList().size)
    println(xs.toMutableList())
}

fun defaulted(vararg xs: Int, prefix: Int = 7) {
    println(prefix)
    println(xs.toList())
}

fun references(vararg xs: String) {
    println(xs.contains("a"))
    println(xs.toList())
}

fun findsLast(vararg xs: Int) = xs.contains(9)

fun main() {
    probeBoolean()
    probeBoolean(*booleanArrayOf())
    probeBoolean(true)
    probeBoolean(*booleanArrayOf(true))
    probeByte()
    probeByte(*byteArrayOf())
    probeByte(1.toByte())
    probeByte(*byteArrayOf(1))
    probeChar()
    probeChar(*charArrayOf())
    probeChar('a')
    probeChar(*charArrayOf('a'))
    probeDouble()
    probeDouble(*doubleArrayOf())
    probeDouble(1.5)
    probeDouble(*doubleArrayOf(1.5))
    probeFloat()
    probeFloat(*floatArrayOf())
    probeFloat(1.5f)
    probeFloat(*floatArrayOf(1.5f))
    probeInt()
    probeInt(*intArrayOf())
    probeInt(1)
    probeInt(*intArrayOf(1))
    probeLong()
    probeLong(*longArrayOf())
    probeLong(1L)
    probeLong(*longArrayOf(1L))
    probeShort()
    probeShort(*shortArrayOf())
    probeShort(1.toShort())
    probeShort(*shortArrayOf(1))
    println(findsLast(1, 9))
    println(findsLast(1, 2))
    defaulted()
    defaulted(1)
    references()
    references("a")
    println(intArrayOf(1).contains(1))
    println(intArrayOf().toList())
}
