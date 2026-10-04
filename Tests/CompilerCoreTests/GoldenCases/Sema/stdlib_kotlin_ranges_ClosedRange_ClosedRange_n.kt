package golden.sema

class StringBounds(
    override val start: String,
    override val endInclusive: String,
) : ClosedRange<String>

fun closedRangeStart(range: ClosedRange<String>): String = range.start

fun closedRangeEndInclusive(range: ClosedRange<String>): String = range.endInclusive

fun closedRangeContains(range: ClosedRange<String>, value: String): Boolean =
    range.contains(value)

fun closedRangeIsEmpty(range: ClosedRange<String>): Boolean = range.isEmpty()

fun closedRangeInOperator(range: ClosedRange<String>, value: String): Boolean =
    value in range

fun inspectInt(range: ClosedRange<Int>) {
    println(range.start)
    println(range.endInclusive)
    println(range.contains(3))
    println(range.isEmpty())
}

fun main() {
    val range: ClosedRange<String> = StringBounds("b", "d")
    println(closedRangeStart(range))
    println(closedRangeEndInclusive(range))
    println(closedRangeContains(range, "c"))
    println(closedRangeIsEmpty(range))
    println(closedRangeInOperator(range, "a"))
    inspectInt(1..5)
}
