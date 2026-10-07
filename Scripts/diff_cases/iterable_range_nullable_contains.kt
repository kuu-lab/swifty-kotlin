fun <T, R> closedContains(range: R, value: T?): Boolean where T : Comparable<T>, R : ClosedRange<T>, R : Iterable<T> {
    return range.contains(value)
}

fun <T, R> openContains(range: R, value: T?): Boolean where T : Comparable<T>, R : OpenEndRange<T>, R : Iterable<T> {
    return value in range
}

fun main() {
    val absent: Int? = null
    val inside: Int? = 3
    val outside: Int? = 7
    val range = 1..5
    println(range.contains(null))
    println(range.contains(absent))
    println(range.contains(inside))
    println(range.contains(outside))
    println(absent in range)
    println(inside in range)
    println(outside !in range)
    println(absent !in range)
    println(inside in 5..1)
    val longValue: Long? = 3L
    val noLong: Long? = null
    println((1L..5L).contains(longValue))
    println(noLong in 1L..5L)
    val charValue: Char? = 'c'
    val noChar: Char? = null
    println(('a'..'e').contains(charValue))
    println(noChar in 'a'..'e')
    val unsignedValue: UInt? = 3u
    val noUInt: UInt? = null
    println((1u..5u).contains(unsignedValue))
    println(noUInt in 1u..5u)
    val ulongValue: ULong? = 3uL
    val noULong: ULong? = null
    println((1uL..5uL).contains(ulongValue))
    println(noULong in 1uL..5uL)
    println(3 in range)
    println(range.contains(7))
    val ints: IntRange = 1..5
    val longs: LongRange = 1L..5L
    val chars: CharRange = 'a'..'e'
    val uints: UIntRange = 1u..5u
    val ulongs: ULongRange = 1uL..5uL
    println(closedContains(ints, inside))
    println(closedContains(ints, absent))
    println(closedContains(longs, longValue))
    println(openContains(longs, noLong))
    println(closedContains(chars, charValue))
    println(openContains(uints, unsignedValue))
    println(openContains(ulongs, ulongValue))
    println(closedContains(ulongs, noULong))
    val allUnsigned: ULongRange = 1uL..18446744073709551615uL
    val unsignedBoundary: ULong? = 9223372036854775808uL
    println(closedContains(allUnsigned, unsignedBoundary))
    println(allUnsigned.contains(unsignedBoundary))
    val minimum: Long? = Long.MIN_VALUE
    val minimumRange: LongRange = Long.MIN_VALUE..(Long.MIN_VALUE + 2L)
    println(closedContains(minimumRange, minimum))
    println(minimumRange.contains(minimum))
}
