class KSP965IntIterable(private val values: List<Int>) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

fun main() {
    val bytes: Iterable<Byte> = listOf(1.toByte(), 2.toByte(), 4.toByte())
    val doubles: Iterable<Double> = listOf(1.0, 2.5, 3.5)
    val floats: Iterable<Float> = listOf(16_777_216.0f, 1.0f)
    val ints: Iterable<Int> = listOf(1, 2, 4)
    val longs: Iterable<Long> = listOf(9_007_199_254_740_992L, 1L)
    val shorts: Iterable<Short> = listOf(1.toShort(), 2.toShort(), 4.toShort())
    val empty: Iterable<Int> = emptyList()
    val custom: Iterable<Int> = KSP965IntIterable(listOf(1, 2, 4))

    println(bytes.average())
    println(doubles.average())
    println(floats.average())
    println(ints.average())
    println(longs.average())
    println(shorts.average())
    println(empty.average())
    println(custom.average())

    val listInts = listOf(1, 3)
    val listDoubles = listOf(1.0, 3.0)
    println(listInts.average())
    println(listDoubles.average())
}
