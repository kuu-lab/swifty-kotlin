fun main() {
    val nullableItems: Iterable<String?> = listOf("a", null, "a", "b")
    val collectionDestination: MutableCollection<Any?> = mutableListOf<Any?>("seed")
    val collectionResult: MutableCollection<Any?> = nullableItems.toCollection(collectionDestination)
    val hashSetResult: HashSet<String?> = nullableItems.toHashSet()
    val setResult: Set<String?> = nullableItems.toSet()

    val nullablePairs: Iterable<Pair<String?, Int?>> = listOf(
        "a" to 1,
        null to null,
        "a" to 2
    )
    val mapResult: Map<String?, Int?> = nullablePairs.toMap()
    val mapDestination: MutableMap<Any?, Any?> = mutableMapOf<Any?, Any?>("keep" to 9)
    val mapDestinationResult: MutableMap<Any?, Any?> = nullablePairs.toMap(mapDestination)

    val listSetResult: Set<Int> = listOf(1, 2, 1).toSet()
    val sequenceSetResult: Set<Int> = sequenceOf(1, 2, 1).toSet()
    val textDestination: MutableCollection<Char> = mutableListOf<Char>('!')
    val textCollectionResult: MutableCollection<Char> = "ab".toCollection(textDestination)

    println(collectionResult)
    println(hashSetResult)
    println(setResult)
    println(mapResult)
    println(mapDestinationResult)
    println(listSetResult)
    println(sequenceSetResult)
    println(textCollectionResult)
}
