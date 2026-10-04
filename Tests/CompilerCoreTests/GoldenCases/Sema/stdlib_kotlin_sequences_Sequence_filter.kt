fun main() {
    val values = sequenceOf(1, 2, 3, 4)

    val filterDestination = mutableListOf(99)
    values.filterTo(filterDestination) { it % 2 == 0 }

    val filterNotDestination = mutableListOf(99)
    values.filterNotTo(filterNotDestination) { it % 2 == 0 }

    val indexedDestination = mutableListOf(99)
    values.filterIndexedTo(indexedDestination) { index, value -> index % 2 == 0 || value == 4 }

    val nullableValues = sequenceOf<Int?>(1, null, 2, null)
    val notNullDestination = mutableListOf(99)
    nullableValues.filterNotNullTo(notNullDestination)

    val mixed: Sequence<Any?> = sequenceOf(1, "two", 3, null)
    mixed.filterIsInstance<Int>().toList()

    val instanceDestination = mutableListOf(0)
    mixed.filterIsInstanceTo<Int, MutableList<Int>>(instanceDestination)
}
