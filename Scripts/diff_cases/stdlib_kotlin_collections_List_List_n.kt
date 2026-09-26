// KSP-1063: kotlin.collections.List member APIs on a List-typed receiver —
// size, isEmpty, indexed get, iterator(), listIterator(), listIterator(index),
// and the for-loop desugared iterator.

fun render(values: List<Int>) {
    println(values.size)
    println(values.isEmpty())
    println(values[1])
    println(values.listIterator().next())
    val indexed = values.listIterator(1)
    println(indexed.previous())
    println(indexed.next())
}

fun sumWithIterator(values: List<Int>): Int {
    val iterator = values.iterator()
    var sum = 0
    while (iterator.hasNext()) {
        sum += iterator.next()
    }
    return sum
}

fun sumWithFor(values: List<Int>): Int {
    var sum = 0
    for (value in values) {
        sum += value
    }
    return sum
}

fun main() {
    render(listOf(4, 5, 6))
    println(sumWithIterator(listOf(1, 2, 3)))
    println(sumWithFor(listOf(10, 20)))
    println(emptyList<Int>().size)
    println(emptyList<Int>().isEmpty())
}
