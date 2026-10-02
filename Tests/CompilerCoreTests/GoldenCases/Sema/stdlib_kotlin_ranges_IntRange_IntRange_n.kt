package golden.sema

fun inspectIntRange(ranges: List<IntRange>) {
    val range = ranges.first()
    println("${range.start},${range.endInclusive},${range.endExclusive},${range.isEmpty()}")
    println(range.toString())
    println(range.hashCode())
    println(range == ranges.first())
    println(range.equals(ranges.first()))
}
