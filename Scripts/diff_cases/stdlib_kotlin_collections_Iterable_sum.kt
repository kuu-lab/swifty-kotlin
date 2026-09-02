private fun byteSum(values: Iterable<Byte>): Int = values.sum()
private fun shortSum(values: Iterable<Short>): Int = values.sum()
private fun intSum(values: Iterable<Int>): Int = values.sum()
private fun longSum(values: Iterable<Long>): Long = values.sum()
private fun floatSum(values: Iterable<Float>): Float = values.sum()
private fun doubleSum(values: Iterable<Double>): Double = values.sum()
private fun ubyteSum(values: Iterable<UByte>): UInt = values.sum()
private fun ushortSum(values: Iterable<UShort>): UInt = values.sum()
private fun uintSum(values: Iterable<UInt>): UInt = values.sum()
private fun ulongSum(values: Iterable<ULong>): ULong = values.sum()

private fun sumOfDouble(values: Iterable<String>): Double = values.sumOf { it.length.toDouble() }
private fun sumOfInt(values: Iterable<String>): Int = values.sumOf { it.length }
private fun sumOfLong(values: Iterable<String>): Long = values.sumOf { it.length.toLong() }
private fun sumOfUInt(values: Iterable<String>): UInt = values.sumOf { it.length.toUInt() }
private fun sumOfULong(values: Iterable<String>): ULong = values.sumOf { it.length.toULong() }

private class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    private var consumed = false

    override fun iterator(): Iterator<T> {
        if (consumed) throw IllegalStateException("one-shot iterable reused")
        consumed = true
        return values.iterator()
    }
}

fun main() {
    println(byteSum(listOf(1.toByte(), 2.toByte(), 3.toByte())))
    println(shortSum(listOf(4.toShort(), 5.toShort())))
    println(intSum(listOf(6, 7)))
    println(longSum(listOf(8L, 9L)))
    println(floatSum(listOf(1.5f, 2.25f)))
    println(doubleSum(listOf(3.5, 4.25)))
    println(ubyteSum(listOf(10.toUByte(), 11.toUByte())))
    println(ushortSum(listOf(12.toUShort(), 13.toUShort())))
    println(uintSum(listOf(14u, 15u)))
    println(ulongSum(listOf(16uL, 17uL)))

    val words: Iterable<String> = listOf("a", "bb", "ccc")
    println(sumOfDouble(words))
    println(sumOfInt(words))
    println(sumOfLong(words))
    println(sumOfUInt(words))
    println(sumOfULong(words))

    val emptyByte: Iterable<Byte> = listOf()
    val emptyDouble: Iterable<Double> = listOf()
    val emptyUInt: Iterable<UInt> = listOf()
    println(emptyByte.sum())
    println(emptyDouble.sum())
    println(emptyUInt.sum())

    val intOverflow: Iterable<Int> = listOf(Int.MAX_VALUE, 1)
    val longOverflow: Iterable<Long> = listOf(Long.MAX_VALUE, 1L)
    val uintOverflow: Iterable<UInt> = listOf(UInt.MAX_VALUE, 1u)
    val ulongOverflow: Iterable<ULong> = listOf(ULong.MAX_VALUE, 1uL)
    println(intOverflow.sum())
    println(longOverflow.sum())
    println(uintOverflow.sum())
    println(ulongOverflow.sum())

    val floatOrder: Iterable<Float> = listOf(1.0e20f, -1.0e20f, 3.0f)
    val doubleOrder: Iterable<Double> = listOf(1.0e20, -1.0e20, 3.0)
    println(floatOrder.sum())
    println(doubleOrder.sum())

    val nullableWords: Iterable<String?> = OneShotIterable(listOf("a", null, "ccc"))
    println(nullableWords.sumOf { it?.length ?: 0 })

    println(OneShotIterable(listOf(1, 2, 3)).sum())

    val visited: Iterable<Int> = OneShotIterable(listOf(1, 2, 3))
    var visitCount = 0
    var visitOrder = 0
    println(visited.sumOf {
        visitCount += 1
        visitOrder = visitOrder * 10 + it
        it
    })
    println(visitCount)
    println(visitOrder)

    var seenBeforeException = 0
    try {
        OneShotIterable(listOf(1, 2, 3)).sumOf {
            if (it == 3) throw IllegalStateException("selector stop")
            seenBeforeException = seenBeforeException * 10 + it
            it
        }
    } catch (_: IllegalStateException) {
        println(seenBeforeException)
    }
}
