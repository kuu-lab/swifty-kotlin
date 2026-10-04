fun partitionIterable(values: Iterable<Int>): Pair<List<Int>, List<Int>> {
    val (matching, rest) = values.partition { it % 2 == 0 }
    return Pair(matching, rest)
}

fun partitionNullable(values: Iterable<String?>): Pair<List<String?>, List<String?>> {
    val result = values.partition { it == null }
    return result.component1() to result.component2()
}
