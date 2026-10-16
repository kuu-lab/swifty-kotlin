// KUU-2200: Kotlin supports every signed primitive rangeTo pairing.
private fun matchesIntRange(range: IntRange, endInclusive: Int): Boolean =
    range.first == 1 && range.last == endInclusive && 1 in range && endInclusive in range

private fun matchesLongRange(range: LongRange, endInclusive: Long): Boolean =
    range.first == 1L && range.last == endInclusive && 1L in range && endInclusive in range

fun box(): String {
    val byteStart: Byte = 1
    val byteEnd: Byte = 2
    val shortStart: Short = 1
    val shortEnd: Short = 2
    val intStart: Int = 1
    val intEnd: Int = 2
    val longStart: Long = 1L
    val longEnd: Long = 2_147_483_650L

    if (!matchesIntRange(byteStart.rangeTo(byteEnd), 2) || !matchesIntRange(byteStart..byteEnd, 2)
        || !matchesIntRange(byteStart.rangeTo(shortEnd), 2) || !matchesIntRange(byteStart..shortEnd, 2)
        || !matchesIntRange(byteStart.rangeTo(intEnd), 2) || !matchesIntRange(byteStart..intEnd, 2)
        || !matchesLongRange(byteStart.rangeTo(longEnd), longEnd) || !matchesLongRange(byteStart..longEnd, longEnd)
        || !matchesIntRange(shortStart.rangeTo(byteEnd), 2) || !matchesIntRange(shortStart..byteEnd, 2)
        || !matchesIntRange(shortStart.rangeTo(shortEnd), 2) || !matchesIntRange(shortStart..shortEnd, 2)
        || !matchesIntRange(shortStart.rangeTo(intEnd), 2) || !matchesIntRange(shortStart..intEnd, 2)
        || !matchesLongRange(shortStart.rangeTo(longEnd), longEnd) || !matchesLongRange(shortStart..longEnd, longEnd)
        || !matchesIntRange(intStart.rangeTo(byteEnd), 2) || !matchesIntRange(intStart..byteEnd, 2)
        || !matchesIntRange(intStart.rangeTo(shortEnd), 2) || !matchesIntRange(intStart..shortEnd, 2)
        || !matchesIntRange(intStart.rangeTo(intEnd), 2) || !matchesIntRange(intStart..intEnd, 2)
        || !matchesLongRange(intStart.rangeTo(longEnd), longEnd) || !matchesLongRange(intStart..longEnd, longEnd)
        || !matchesLongRange(longStart.rangeTo(byteEnd), 2L) || !matchesLongRange(longStart..byteEnd, 2L)
        || !matchesLongRange(longStart.rangeTo(shortEnd), 2L) || !matchesLongRange(longStart..shortEnd, 2L)
        || !matchesLongRange(longStart.rangeTo(intEnd), 2L) || !matchesLongRange(longStart..intEnd, 2L)
        || !matchesLongRange(longStart.rangeTo(longEnd), longEnd) || !matchesLongRange(longStart..longEnd, longEnd)
    ) return "FAIL"

    return "OK"
}

fun main() {
    val result = box()
    if (result != "OK") throw IllegalStateException("Unexpected range result: $result")
    println(result)
}
