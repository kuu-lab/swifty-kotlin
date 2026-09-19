fun main() {
    val intRange: IntRange = IntRange(1, 3)
    println(intRange.start)
    println(intRange.endInclusive)
    println(intRange.endExclusive)
    println(2 in intRange)
    println(intRange.isEmpty())

    val longRange: LongRange = LongRange(4L, 6L)
    println(longRange.start)
    println(longRange.endInclusive)
    println(longRange.endExclusive)
    println(5L in longRange)
    println(longRange.isEmpty())

    val charRange: CharRange = CharRange('a', 'c')
    println(charRange.start)
    println(charRange.endInclusive)
    println(charRange.endExclusive)
    println('b' in charRange)
    println(charRange.isEmpty())

    var sum = 0
    for (value in intRange) {
        sum += value
    }
    println(sum)
}
