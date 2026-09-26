private fun longSum(values: Sequence<Long>): Long = values.sum()
private fun floatSum(values: Sequence<Float>): Float = values.sum()
private fun doubleSum(values: Sequence<Double>): Double = values.sum()
private fun ubyteSum(values: Sequence<UByte>): UInt = values.sum()
private fun ushortSum(values: Sequence<UShort>): UInt = values.sum()
private fun uintSum(values: Sequence<UInt>): UInt = values.sum()
private fun ulongSum(values: Sequence<ULong>): ULong = values.sum()

private fun sumOfInt(values: Sequence<String>): Int = values.sumOf { it.length }
private fun sumOfDouble(values: Sequence<String>): Double = values.sumOf { it.length.toDouble() }
private fun sumOfLong(values: Sequence<String>): Long = values.sumOf { it.length.toLong() }
private fun sumOfUInt(values: Sequence<String>): UInt = values.sumOf { it.length.toUInt() }
private fun sumOfULong(values: Sequence<String>): ULong = values.sumOf { it.length.toULong() }

fun main() {
    println(sequenceOf(6, 7).sum())
    println(longSum(sequenceOf(8L, 9L)))
    println(floatSum(sequenceOf(1.5f, 2.25f)))
    println(doubleSum(sequenceOf(3.5, 4.25)))
    println(ubyteSum(sequenceOf(10.toUByte(), 11.toUByte())))
    println(ushortSum(sequenceOf(12.toUShort(), 13.toUShort())))
    println(uintSum(sequenceOf(14u, 15u)))
    println(ulongSum(sequenceOf(16uL, 17uL)))

    val words: Sequence<String> = sequenceOf("a", "bb", "ccc")
    println(sumOfInt(words))
    println(sumOfDouble(words))
    println(sumOfLong(words))
    println(sumOfUInt(words))
    println(sumOfULong(words))

    println(emptySequence<Double>().sum())
    println(emptySequence<UInt>().sum())
    println(emptySequence<ULong>().sum())
    println(emptySequence<Int>().sumOf { it })

    val longOverflow: Sequence<Long> = sequenceOf(Long.MAX_VALUE, 1L)
    val uintOverflow: Sequence<UInt> = sequenceOf(UInt.MAX_VALUE, 1u)
    val ulongOverflow: Sequence<ULong> = sequenceOf(ULong.MAX_VALUE, 1uL)
    println(longOverflow.sum())
    println(uintOverflow.sum())
    println(ulongOverflow.sum())

    println(sequenceOf(200.toUByte(), 100.toUByte()).sum())
    println(sequenceOf(60000.toUShort(), 10000.toUShort()).sum())

    val floatOrder: Sequence<Float> = sequenceOf(1.0e20f, -1.0e20f, 3.0f)
    val doubleOrder: Sequence<Double> = sequenceOf(1.0e20, -1.0e20, 3.0)
    println(floatOrder.sum())
    println(doubleOrder.sum())

    val nullableWords: Sequence<String?> = sequenceOf("a", null, "ccc")
    println(nullableWords.sumOf { it?.length ?: 0 })

    val visited: Sequence<Int> = sequenceOf(1, 2, 3)
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
        sequenceOf(1, 2, 3).sumOf {
            if (it == 3) throw IllegalStateException("selector stop")
            seenBeforeException = seenBeforeException * 10 + it
            it
        }
    } catch (_: IllegalStateException) {
        println(seenBeforeException)
    }

    // Lazy evaluation: map/sumOf must not iterate the source eagerly.
    var mapped = 0
    val lazy: Sequence<Int> = generateSequence(1) { if (it < 3) it + 1 else null }
        .map {
            mapped = mapped * 10 + it
            it
        }
    println(mapped)
    println(lazy.sum())
    println(mapped)

    // A non-reusable sequence can still be summed once.
    val oneShot: Sequence<Int> = listOf(1, 2, 3).asSequence()
    println(oneShot.sum())

    println(listOf("x", "yy").asSequence().sumOf { it.length })
}
