@file:OptIn(ExperimentalUnsignedTypes::class)

import kotlin.comparisons.compareValues
import kotlin.comparisons.reverseOrder

private class Rank(val value: Int) : Comparable<Rank> {
    override fun compareTo(other: Rank): Int = value.compareTo(other.value)
}

private fun checkReceivers() {
    val increasing: Iterable<Int> = listOf(1, 2, 2, 3)
    check(increasing.isSorted())
    check(!increasing.isSortedDescending())
    check(emptyList<Int>().isSorted())
    check(listOf(1).isSortedDescending())
    check(emptyList<Int>().isSortedBy { error("empty iterable") })
    check(!setOf(3, 1, 2).isSortedBy { it })
    check(listOf(3, 2, 2, 1).isSortedByDescending { it })
    check(listOf(3, 2, 1).isSortedWith(reverseOrder<Int>()))

    check(sequenceOf(1, 2, 2, 3).isSorted())
    check(sequenceOf(3, 2, 1).isSortedDescending())
    check(sequenceOf(3, 2, 1).isSortedWith(reverseOrder<Int>()))
    check(sequenceOf(3, 2, 2, 1).isSortedByDescending { it })
    check(emptySequence<Int>().isSortedBy { error("empty sequence") })
    check(sequenceOf(1).isSortedByDescending { error("single sequence element") })

    val ranks: Array<out Rank> = arrayOf(Rank(1), Rank(2), Rank(2))
    val byRank: Comparator<Any> = Comparator { a, b -> (a as Rank).compareTo(b as Rank) }
    check(ranks.isSorted())
    check(!ranks.isSortedDescending())
    check(ranks.isSortedWith(byRank))
    check(ranks.isSortedBy { it.value })
    check(!ranks.isSortedByDescending { it })
    check(emptyArray<Rank>().isSorted())
    check(arrayOf(Rank(1)).isSortedBy { error("single array element") })
    check(listOf(Rank(2), Rank(1)).isSortedDescending())
}

private fun checkPrimitiveArrays() {
    check(byteArrayOf(-128, 0, 127).isSorted())
    check(shortArrayOf(32767, 0, -32768).isSortedDescending())
    check(intArrayOf().isSortedDescending())
    check(intArrayOf().isSortedBy { error("empty primitive array") })
    check(intArrayOf(1, 2, 2).isSortedWith(Comparator<Int> { a, b -> a.compareTo(b) }))
    check(intArrayOf(3, 2, 1).isSortedByDescending { it })
    check(!longArrayOf(Long.MAX_VALUE, Long.MIN_VALUE).isSorted())
    check(charArrayOf('A', 'a').isSorted())
    check(booleanArrayOf(false, false, true).isSorted())
    check(!booleanArrayOf(false, true).isSortedDescending())
    check(booleanArrayOf(true, false).isSortedBy { !it })

    check(ubyteArrayOf(0u, 127u, 255u).isSorted())
    check(ushortArrayOf(65535u, 1u).isSortedDescending())
    check(uintArrayOf(0u, UInt.MAX_VALUE).isSortedWith(Comparator<UInt> { a, b -> a.compareTo(b) }))
    check(ulongArrayOf(0uL, ULong.MAX_VALUE).isSorted())
    check(!ulongArrayOf(0uL, ULong.MAX_VALUE).isSortedDescending())
    check(ulongArrayOf(ULong.MAX_VALUE, 0uL).isSortedByDescending { it })
    check(uintArrayOf(0u, UInt.MAX_VALUE).isSortedBy { it })
}

private fun checkNullableKeys() {
    val nullable = listOf(null, null, 1, 2)
    check(nullable.isSortedBy { it })
    check(!nullable.isSortedByDescending { it })
    check(sequenceOf(2, 1, null, null).isSortedByDescending { it })
    check(arrayOf(null, null, 1, 2).isSortedWith(Comparator<Int?> { a, b -> compareValues(a, b) }))
    check(!arrayOf(1, null, 2).isSortedBy { it })
    check(arrayOf(2, 1, null).isSortedByDescending { it })
    check(intArrayOf(0, 1, 2).isSortedBy { if (it == 0) null else it })
    check(ubyteArrayOf(2u, 1u, 0u).isSortedByDescending { if (it.toInt() == 0) null else it })
}

private fun checkFloatingPointOrder() {
    val floats = floatArrayOf(Float.NEGATIVE_INFINITY, -0.0f, 0.0f, Float.POSITIVE_INFINITY, Float.NaN, Float.NaN)
    check(floats.isSorted())
    check(!floats.isSortedDescending())
    check(!floatArrayOf(0.0f, -0.0f).isSorted())
    check(floatArrayOf(0.0f, -0.0f).isSortedDescending())
    check(floatArrayOf(Float.NaN, 0.0f).isSortedDescending())
    check(!floatArrayOf(Float.NaN, 0.0f).isSorted())

    val doubles = doubleArrayOf(Double.NaN, Double.NaN, Double.POSITIVE_INFINITY, 0.0, -0.0, Double.NEGATIVE_INFINITY)
    check(doubles.isSortedDescending())
    check(!doubles.isSorted())
    check(doubleArrayOf(-0.0, 0.0).isSorted())
    check(!doubleArrayOf(-0.0, 0.0).isSortedDescending())
    check(!doubleArrayOf(Double.NaN, 0.0).isSorted())
    check(!doubleArrayOf(0.0, Double.NaN).isSortedDescending())
    check(!doubleArrayOf(Double.NaN, 0.0).isSortedBy { it })
    check(!floatArrayOf(-0.0f, 0.0f).isSortedByDescending { it })
    check(listOf(-0.0, 0.0, Double.NaN).isSorted())
    check(!arrayOf(Float.NaN, 0.0f).isSorted())
}

private fun checkCallbackOrder() {
    val trace = StringBuilder()
    val comparator = Comparator<Int> { a, b ->
        trace.append("$a:$b;")
        a.compareTo(b)
    }
    check(!listOf(1, 3, 2, 4).isSortedWith(comparator))
    check(trace.toString() == "1:3;3:2;")
    check(emptyList<Int>().isSortedWith(comparator))
    check(intArrayOf(1).isSortedWith(comparator))
    check(trace.toString() == "1:3;3:2;")

    // Array comparisons read both operands of each pair, even after mutation.
    val values = arrayOf(1, 2, 3, 4)
    val mutatingComparator = Comparator<Int> { a, b ->
        values[1] = 10
        a.compareTo(b)
    }
    check(!values.isSortedWith(mutatingComparator))

    val ascendingTrace = StringBuilder()
    check(!intArrayOf(1, 3, 2, 4).isSortedBy {
        ascendingTrace.append(it)
        it
    })
    check(ascendingTrace.toString() == "132")

    val descendingTrace = StringBuilder()
    check(!arrayOf(4, 2, 3, 1).isSortedByDescending {
        descendingTrace.append(it)
        it
    })
    check(descendingTrace.toString() == "423")

    val sequenceTrace = StringBuilder()
    val valuesFromSequence = generateSequence(1) {
        sequenceTrace.append("next$it;")
        when (it) {
            1 -> 3
            3 -> 2
            else -> error("sequence consumed past the first disorder")
        }
    }
    check(!valuesFromSequence.isSortedBy {
        sequenceTrace.append("key$it;")
        it
    })
    check(sequenceTrace.toString() == "next1;key1;key3;next3;key2;")
}

private fun iterableNonLocalReturn(values: Iterable<Int>): String {
    values.isSortedBy { if (it == 2) return "returned" else it }
    return "completed"
}

private fun sequenceNonLocalReturn(values: Sequence<Int>): String {
    values.isSortedByDescending { if (it == 2) return "returned" else it }
    return "completed"
}

private fun arrayNonLocalReturn(values: UIntArray): String {
    values.isSortedBy { if (it == 2u) return "returned" else it }
    return "completed"
}

fun main() {
    checkReceivers()
    checkPrimitiveArrays()
    checkNullableKeys()
    checkFloatingPointOrder()
    checkCallbackOrder()
    check(iterableNonLocalReturn(listOf(1, 2, 3)) == "returned")
    check(sequenceNonLocalReturn(sequenceOf(3, 2, 1)) == "returned")
    check(arrayNonLocalReturn(uintArrayOf(1u, 2u, 3u)) == "returned")
    println("OK")
}
