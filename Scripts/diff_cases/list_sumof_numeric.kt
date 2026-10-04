fun main() {
    val values = listOf(1, 2, 3)
    println(values.sumOf { it })
    println(values.sumOf { it.toLong() })
    println(values.sumOf { it.toDouble() })
    println(emptyList<Int>().sumOf { it.toLong() })
    println(emptyList<Int>().sumOf { it.toDouble() })

    // BUG-256 sibling: List<T>.sumOf has no concrete UInt/ULong overload
    // (only Int/Long/Double in ListAggregateHOF.kt), so these must fall
    // back to the generic Iterable<T>.sumOf family.
    println(values.sumOf { it.toUInt() })
    println(values.sumOf { it.toULong() })
    println(emptyList<Int>().sumOf { it.toUInt() })
    println(emptyList<Int>().sumOf { it.toULong() })
    println(listOf(Int.MAX_VALUE, 1).sumOf { it.toUInt() })
}
