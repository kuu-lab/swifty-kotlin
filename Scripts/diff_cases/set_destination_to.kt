fun main() {
    // KUU-1389: Set/Collection-family receivers inherit these destination HOFs
    // from Iterable<T>; they used to link against phantom `_filterTo`-style
    // symbols instead of the bundled Iterable declarations.
    val setFilterDestination = mutableListOf(99)
    println(setOf(1, 2, 3).filterTo(setFilterDestination) { it > 1 })

    val setFilterNotDestination = mutableListOf(99)
    println(setOf(1, 2, 3).filterNotTo(setFilterNotDestination) { it > 1 })

    val setFilterIndexedDestination = mutableListOf(99)
    println(setOf(10, 20, 30).filterIndexedTo(setFilterIndexedDestination) { index, _ -> index % 2 == 0 })

    val mutableSetDestination = mutableListOf(0)
    println(mutableSetOf(1, 2, 3).filterTo(mutableSetDestination) { it > 1 })

    val collection: Collection<Int> = listOf(1, 2, 3)
    val collectionDestination = mutableListOf(0)
    println(collection.filterTo(collectionDestination) { it > 1 })

    val map = mapOf(1 to "a", 2 to "b")
    println(map.entries.filterTo(mutableListOf()) { it.key > 1 })
    println(map.entries.filterNotTo(mutableListOf()) { it.key > 1 })
    println(map.keys.filterTo(mutableListOf()) { it > 1 })
    println(map.values.filterTo(mutableListOf()) { it == "b" })
}
