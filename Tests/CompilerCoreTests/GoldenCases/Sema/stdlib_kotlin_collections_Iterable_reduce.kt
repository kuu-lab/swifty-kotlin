fun inspectReduceFamily(values: Iterable<Int>): Unit {
    val reduced: Number = values.reduce { acc: Number, value -> acc.toInt() + value }
    val indexed: Number = values.reduceIndexed { index, acc: Number, value -> acc.toInt() + index + value }
    val reducedOrNull: Number? = values.reduceOrNull { acc: Number, value -> acc.toInt() + value }
    val indexedOrNull: Number? = values.reduceIndexedOrNull { index, acc: Number, value -> acc.toInt() + index + value }
    println(reduced)
    println(indexed)
    println(reducedOrNull)
    println(indexedOrNull)
}
