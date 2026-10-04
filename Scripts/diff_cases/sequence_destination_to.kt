fun main() {
    val filterDestination = mutableListOf(99)
    println(sequenceOf(-2, -1, 0, 1, 2).filterTo(filterDestination) { it > 0 })

    val filterNotDestination = mutableListOf(99)
    println(sequenceOf(-2, -1, 0, 1, 2).filterNotTo(filterNotDestination) { it > 0 })

    val mapDestination = mutableListOf(99)
    println(sequenceOf(1, 2, 3).mapTo(mapDestination) { it * 10 })

    val mapNotNullDestination = mutableListOf(99)
    println(sequenceOf(1, 2, 3, 4).mapNotNullTo(mapNotNullDestination) { if (it % 2 == 0) it * 10 else null })

    val mapIndexedDestination = mutableListOf(99)
    println(sequenceOf(10, 20, 30).mapIndexedTo(mapIndexedDestination) { index, value -> index + value })

    val flatMapDestination = mutableListOf(99)
    println(sequenceOf(1, 2).flatMapTo(flatMapDestination) { listOf(it, it * 10) })

    val filterIndexedDestination = mutableListOf(99)
    println(sequenceOf(10, 20, 30, 40).filterIndexedTo(filterIndexedDestination) { index, value -> index % 2 == 0 || value == 40 })

    val mapIndexedNotNullDestination = mutableListOf(99)
    println(sequenceOf(1, 2, 3, 4).mapIndexedNotNullTo(mapIndexedNotNullDestination) { index, value -> if (index % 2 == 0) index + value else null })

    val flatMapIndexedDestination = mutableListOf(99)
    println(sequenceOf(1, 2).flatMapIndexedTo(flatMapIndexedDestination) { index, value -> listOf(index, value * 10) })

    val filterNotNullDestination = mutableListOf(99)
    println(sequenceOf<Int?>(1, null, 2, null).filterNotNullTo(filterNotNullDestination))

    val filterIsInstanceDestination = mutableListOf(0)
    println(sequenceOf<Any?>(1, "two", 3).filterIsInstanceTo<Int, MutableList<Int>>(filterIsInstanceDestination))
}
