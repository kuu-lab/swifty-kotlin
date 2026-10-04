private class CountingIntComparator : Comparator<Int> {
    var calls: Int = 0

    override fun compare(a: Int, b: Int): Int {
        calls++
        return a.compareTo(b)
    }
}

private class ThrowingIntComparator : Comparator<Int> {
    override fun compare(a: Int, b: Int): Int {
        throw IllegalArgumentException("comparator")
    }
}

private fun doubleZeroSign(value: Double): String {
    return if (value == 0.0 && 1.0 / value < 0.0) "negative" else "positive"
}

private fun floatZeroSign(value: Float): String {
    return if (value == 0.0f && 1.0f / value < 0.0f) "negative" else "positive"
}

fun main() {
    val map: Map<String, Int> = linkedMapOf("first" to 2, "second" to 1, "tie" to 1)
    println(map.minBy { it.value }.key)
    println(map.minOf { it.key })
    println(map.minOf { it.value.toDouble() })
    println(map.minOf { it.value.toFloat() })
    println(map.minOfOrNull { it.key })
    println(map.minOfOrNull { it.value.toDouble() })
    println(map.minOfOrNull { it.value.toFloat() })

    val intComparator = CountingIntComparator()
    println(map.minOfWith(intComparator) { it.value })
    println(intComparator.calls)
    println(map.minOfWithOrNull(intComparator) { it.value })
    println(intComparator.calls)
    println(map.minWith(compareBy { it.value }).key)
    println(map.minWithOrNull(compareBy { it.value })?.key)

    val empty = emptyMap<String, Int>()
    println(empty.minOfOrNull { it.value } == null)
    println(empty.minOfOrNull { it.value.toDouble() } == null)
    println(empty.minOfOrNull { it.value.toFloat() } == null)
    println(empty.minOfWithOrNull(naturalOrder<Int>()) { it.value } == null)
    println(empty.minWithOrNull(compareBy { it.value }) == null)
    println(try { empty.minBy { it.value }; false } catch (_: NoSuchElementException) { true })
    println(try { empty.minOf { it.value }; false } catch (_: NoSuchElementException) { true })
    println(try { empty.minOfWith(naturalOrder<Int>()) { it.value }; false } catch (_: NoSuchElementException) { true })
    println(try { empty.minWith(compareBy { it.value }); false } catch (_: NoSuchElementException) { true })

    var selectorCalls = 0
    val one = mapOf("only" to 4)
    println(one.minBy { selectorCalls++; it.value }.key)
    println(selectorCalls)
    println(one.minOfWith(naturalOrder<Int>()) { selectorCalls++; it.value })
    println(selectorCalls)

    val nullableMap: Map<String?, Int?> = linkedMapOf(null to null, "value" to 3)
    println(nullableMap.minBy { it.value ?: Int.MAX_VALUE }.key == null)
    println(nullableMap.minOfOrNull { it.key ?: "" })
    println(nullableMap.minOfWithOrNull(naturalOrder<Int>()) { it.value ?: -1 })
    println(nullableMap.minWithOrNull(compareBy { it.value ?: Int.MAX_VALUE })?.key == null)

    val selectorException = try {
        mapOf("ok" to 1, "boom" to 0).minOf { if (it.key == "boom") throw IllegalStateException("selector") else it.value }
        "none"
    } catch (e: IllegalStateException) {
        e.message
    }
    println(selectorException)
    val comparatorException = try {
        map.minOfWith(ThrowingIntComparator()) { it.value }
        "none"
    } catch (e: IllegalArgumentException) {
        e.message
    }
    println(comparatorException)

    val doubleValues = linkedMapOf(
        "nan" to Double.NaN,
        "negativeZero" to -0.0,
        "positiveZero" to 0.0,
        "positiveInfinity" to Double.POSITIVE_INFINITY,
        "negativeInfinity" to Double.NEGATIVE_INFINITY,
    )
    val doubleMin = doubleValues.minOf { it.value }
    println(doubleMin.isNaN())
    println(doubleZeroSign(linkedMapOf("positive" to 0.0, "negative" to -0.0).minOf { it.value }))
    println(linkedMapOf("positive" to Double.POSITIVE_INFINITY, "negative" to Double.NEGATIVE_INFINITY).minOf { it.value } == Double.NEGATIVE_INFINITY)

    val floatMin = linkedMapOf("nan" to Float.NaN, "one" to 1.0f, "infinity" to Float.POSITIVE_INFINITY).minOfOrNull { it.value }
    println((floatMin ?: 0.0f).isNaN())
    println(floatZeroSign(linkedMapOf("positive" to 0.0f, "negative" to -0.0f).minOfOrNull { it.value } ?: 1.0f))
    println(linkedMapOf("positive" to Float.POSITIVE_INFINITY, "negative" to Float.NEGATIVE_INFINITY).minOfOrNull { it.value } == Float.NEGATIVE_INFINITY)
}
