fun main() {
    val doubles = doubleArrayOf(1.0, 2.5, 3.5)
    println(doubles.fold(0.0) { acc, value -> acc + value })
    println(doubles.fold(1.0) { acc, value -> acc * value })
    println(doubles.foldIndexed(0.0) { index, acc, value -> acc + index * value })
    println(doubles.reduce { acc, value -> acc + value })

    val floats = floatArrayOf(1.0f, 2.5f)
    println(floats.fold(0.0f) { acc, value -> acc + value })

    val ints = intArrayOf(1, 2, 3)
    println(ints.fold(0) { acc, value -> acc + value })
    println(ints.foldIndexed(0) { index, acc, value -> acc + index * value })

    val longs = longArrayOf(1L, 2L, 3L)
    println(longs.fold(0L) { acc, value -> acc + value })

    val chars = charArrayOf('a', 'b', 'c')
    println(chars.fold("") { acc, value -> acc + value })

    println(doubles.fold("") { acc, value -> "$acc[$value]" })
}
