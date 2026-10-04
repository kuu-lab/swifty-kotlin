fun inspectUIntRange(ranges: List<UIntRange>) {
    val range = ranges.first()
    println("${range.start},${range.endInclusive},${range.endExclusive}")
    println(range.isEmpty())
    println(range.toString())
    println(range.hashCode())
    println(range.equals(ranges.first()))
    println(range == ranges.first())
}
