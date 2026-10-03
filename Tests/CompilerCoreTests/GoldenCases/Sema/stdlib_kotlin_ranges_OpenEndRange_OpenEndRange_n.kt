package golden.sema

fun openEndRangeStart(range: OpenEndRange<Int>): Int = range.start

fun openEndRangeEndExclusive(range: OpenEndRange<Int>): Int = range.endExclusive

fun openEndRangeContains(range: OpenEndRange<Int>, value: Int): Boolean =
    range.contains(value)

fun openEndRangeIsEmpty(range: OpenEndRange<Int>): Boolean = range.isEmpty()

fun openEndRangeInOperator(range: OpenEndRange<Int>, value: Int): Boolean =
    value in range

fun openEndRangeCrossContains(range: OpenEndRange<Int>, value: Byte): Boolean =
    range.contains(value)

fun main() {
    val open: OpenEndRange<Int> = 1..<5
    println(open.start)
    println(open.endExclusive)
    println(open.contains(3))
    println(open.isEmpty())
    println(3 in open)
}
