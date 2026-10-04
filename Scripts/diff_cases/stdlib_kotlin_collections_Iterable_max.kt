// KSP-983: source-backed kotlin.collections.Iterable.max-family parity.

private class OneShotIterable<T>(private val source: Iterable<T>) : Iterable<T> {
    override fun iterator(): Iterator<T> = source.iterator()
}

fun main() {
    val values: Iterable<Int> = OneShotIterable(listOf(11, 25, 22, 13))
    val singleton: Iterable<Int> = OneShotIterable(listOf(7))
    val empty: Iterable<Int> = OneShotIterable(emptyList())
    var comparatorCalls = 0
    val comparator = Comparator<Any> { a, b ->
        comparatorCalls += 1
        (a as Int).compareTo(b as Int)
    }

    println("max=" + values.max())
    println("maxBySingleton=" + singleton.maxBy { it })
    println("maxByOrNullEmpty=" + empty.maxByOrNull { it })
    println("maxOf=" + values.maxOf { it / 10 })
    println("maxOfDouble=" + values.maxOf { it.toDouble() / 10.0 })
    println("maxOfFloat=" + values.maxOf { it.toFloat() / 10.0f })
    println("maxOfOrNullEmpty=" + empty.maxOfOrNull { it })
    println("maxOfOrNullDouble=" + values.maxOfOrNull { it.toDouble() / 10.0 })
    println("maxOfOrNullFloat=" + values.maxOfOrNull { it.toFloat() / 10.0f })
    comparatorCalls = 0
    println("maxOfWith=" + values.maxOfWith(comparator) { it / 10 } + ":" + comparatorCalls)
    comparatorCalls = 0
    println("maxOfWithOrNullEmpty=" + empty.maxOfWithOrNull(comparator) { it / 10 } + ":" + comparatorCalls)
    println("maxOrNull=" + values.maxOrNull())
    val doublesSmall: Iterable<Double> = OneShotIterable(listOf(1.0, 5.0, 3.0))
    val floatsSmall: Iterable<Float> = OneShotIterable(listOf(1.0f, 5.0f, 3.0f))
    println("maxOrNullDouble=" + doublesSmall.maxOrNull())
    println("maxOrNullFloat=" + floatsSmall.maxOrNull())
    comparatorCalls = 0
    println("maxWith=" + values.maxWith(comparator) + ":" + comparatorCalls)
    comparatorCalls = 0
    println("maxWithOrNullEmpty=" + empty.maxWithOrNull(comparator) + ":" + comparatorCalls)
    comparatorCalls = 0
    println("maxWithSingleton=" + singleton.maxWith(comparator) + ":" + comparatorCalls)

    var selectorCalls = 0
    println("maxByOneCalls=" + singleton.maxBy { selectorCalls += 1; it } + ":" + selectorCalls)
    selectorCalls = 0
    println("maxByManyCalls=" + values.maxBy { selectorCalls += 1; it / 10 } + ":" + selectorCalls)
    selectorCalls = 0
    println("maxByOrNullEmptyCalls=" + empty.maxByOrNull { selectorCalls += 1; it } + ":" + selectorCalls)

    val doubles: Iterable<Double> = OneShotIterable(listOf(Double.NaN, 0.0, -0.0, Double.POSITIVE_INFINITY))
    val floats: Iterable<Float> = OneShotIterable(listOf(Float.NaN, 0.0f, -0.0f, Float.POSITIVE_INFINITY))
    println("doubleMaxNaN=" + doubles.max().isNaN())
    println("doubleMaxOrNullNaN=" + doubles.maxOrNull()!!.isNaN())
    println("doubleMaxOfNaN=" + doubles.maxOf { it }.isNaN())
    println("doubleMaxOfOrNullNaN=" + doubles.maxOfOrNull { it }!!.isNaN())
    println("floatMaxNaN=" + floats.max().isNaN())
    println("floatMaxOrNullNaN=" + floats.maxOrNull()!!.isNaN())
    println("floatMaxOfNaN=" + floats.maxOf { it }.isNaN())
    println("floatMaxOfOrNullNaN=" + floats.maxOfOrNull { it }!!.isNaN())
    val doubleOrdered: Iterable<Double> = OneShotIterable(listOf(Double.NEGATIVE_INFINITY, 0.0, -0.0, Double.POSITIVE_INFINITY))
    val floatOrdered: Iterable<Float> = OneShotIterable(listOf(Float.NEGATIVE_INFINITY, 0.0f, -0.0f, Float.POSITIVE_INFINITY))
    println("doubleMaxInfinity=" + doubleOrdered.max().isInfinite())
    println("doubleMaxOrNullInfinity=" + doubleOrdered.maxOrNull()!!.isInfinite())
    println("doubleMaxOfInfinity=" + doubleOrdered.maxOf { it }.isInfinite())
    println("doubleMaxOfOrNullInfinity=" + doubleOrdered.maxOfOrNull { it }!!.isInfinite())
    println("floatMaxInfinity=" + floatOrdered.max().isInfinite())
    println("floatMaxOrNullInfinity=" + floatOrdered.maxOrNull()!!.isInfinite())
    println("floatMaxOfInfinity=" + floatOrdered.maxOf { it }.isInfinite())
    println("floatMaxOfOrNullInfinity=" + floatOrdered.maxOfOrNull { it }!!.isInfinite())
    println("doubleSignedZeroPositiveFirst=" + (OneShotIterable(listOf(0.0, -0.0)) as Iterable<Double>).max().let { 1.0 / it })
    println("doubleSignedZeroNegativeFirst=" + (OneShotIterable(listOf(-0.0, 0.0)) as Iterable<Double>).max().let { 1.0 / it })
    println("floatSignedZeroPositiveFirst=" + (OneShotIterable(listOf(0.0f, -0.0f)) as Iterable<Float>).max().let { 1.0f / it })
    println("floatSignedZeroNegativeFirst=" + (OneShotIterable(listOf(-0.0f, 0.0f)) as Iterable<Float>).max().let { 1.0f / it })
}
