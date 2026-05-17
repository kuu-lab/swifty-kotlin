fun main() {
    val totals = sequenceOf(1, 2, 3, 4)
        .runningReduce { acc, value -> acc + value }
        .toList()
    println(totals)

    val products = sequenceOf(2, 3, 4)
        .runningReduce { acc, value -> acc * value }
        .toList()
    println(products)

    val single = sequenceOf(42)
        .runningReduce { acc, value -> acc + value }
        .toList()
    println(single)
}
