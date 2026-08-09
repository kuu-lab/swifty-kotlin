// KSP-628: List → array conversions (object + signed primitive element types).
fun main() {
    val objs = listOf("a", "b", "c").toTypedArray()
    println(objs.size)
    println(objs[0])
    println(objs[2])

    val chars = listOf('x', 'y', 'z').toCharArray()
    println(chars.size)
    println(chars[0])
    println(chars[2])

    val bools = listOf(true, false, true).toBooleanArray()
    println(bools.size)
    println(bools[0])
    println(bools[1])

    val shorts = listOf<Short>(1, -2, 32767).toShortArray()
    println(shorts.size)
    println(shorts[1])
    println(shorts[2])

    val doubles = listOf(1.5, -2.25).toDoubleArray()
    println(doubles.size)
    println(doubles[0])
    println(doubles[1])

    val floats = listOf(1.5f, -2.25f).toFloatArray()
    println(floats.size)
    println(floats[0])
    println(floats[1])

    val ints = listOf(1, -2, 1000000).toIntArray()
    println(ints.size)
    println(ints[1])
    println(ints[2])

    val longs = listOf(1L, -2L, 10000000000L).toLongArray()
    println(longs.size)
    println(longs[1])
    println(longs[2])

    val bytes = listOf<Byte>(1, -2, 127).toByteArray()
    println(bytes.size)
    println(bytes[1])
    println(bytes[2])

    val empty = listOf<Int>().toIntArray()
    println(empty.size)

    println(ints.toList())
    println(bytes.toList())
}
