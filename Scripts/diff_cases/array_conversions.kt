fun main() {
    val arr = arrayOf(1, 2, 3)
    println(arr.toList())
    val list = listOf(4, 5, 6)
    val arr2 = list.toTypedArray()
    println(arr2.size)
    println(arr2[0])
    val collection: Collection<Int> = setOf(7, 8, 7)
    val arr3 = collection.toTypedArray()
    println(arr3.toList())

    val ints = intArrayOf(1, -2, 3)
    println(ints.size)
    println(ints.toList())

    val longs = longArrayOf(10L, -20L)
    println(longs.size)
    println(longs.toList())

    val shorts = shortArrayOf(4, -5)
    println(shorts.size)
    println(shorts.toList())

    val bytes = byteArrayOf(6, -7)
    println(bytes.size)
    println(bytes.toList())

    val chars = charArrayOf('a', 'Z')
    println(chars.size)
    println(chars.toList())

    val booleans = booleanArrayOf(true, false)
    println(booleans.size)
    println(booleans.toList())

    val doubles = doubleArrayOf(1.5, -2.5)
    println(doubles.size)
    println(doubles.toList())

    val floats = floatArrayOf(3.5f, -4.5f)
    println(floats.size)
    println(floats.toList())
}
