fun inspectRunning(values: Iterable<Int>) {
    val reduced = values.runningReduce { acc, value -> acc + value }
    val indexed = values.runningReduceIndexed { index, acc, value -> acc + index + value }
    println(reduced)
    println(indexed)
}

fun inspectOverloads(values: List<Int>) {
    println(values.runningReduce { acc, value -> acc + value })
    println(values.asSequence().runningReduce { acc, value -> acc + value }.toList())
}
