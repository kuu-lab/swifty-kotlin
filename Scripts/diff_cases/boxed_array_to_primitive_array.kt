fun sumInts(vararg xs: Int): Int = xs.sum()

fun main() {
    val ints = arrayOf(1, -2, 3).toIntArray()
    println(ints.size)
    println(ints.toList())
    println(sumInts(*arrayOf(4, 5, 6).toIntArray()))

    val longs = arrayOf(10L, -20L).toLongArray()
    println(longs.toList())

    val shorts = arrayOf<Short>(4, -5).toShortArray()
    println(shorts.toList())

    val bytes = arrayOf<Byte>(6, -7).toByteArray()
    println(bytes.toList())

    val chars = arrayOf('a', 'Z').toCharArray()
    println(chars.toList())
    println(chars.concatToString())

    val doubles = arrayOf(1.5, -2.25).toDoubleArray()
    println(doubles.toList())

    val floats = arrayOf(1.5f, -2.5f).toFloatArray()
    println(floats.toList())

    val booleans = arrayOf(true, false, true).toBooleanArray()
    println(booleans.toList())

    val empty = emptyArray<Int>().toIntArray()
    println(empty.size)

    val boxed: Array<Int> = Array(3) { it * it }
    val copy = boxed.toIntArray()
    boxed[0] = 99
    println(copy.toList())
    println(boxed.toList())
}
