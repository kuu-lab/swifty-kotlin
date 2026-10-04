fun main() {
    val source = sequenceOf("first" to 1, "second" to 2, "first" to 3)
    val fresh: Map<String, Int> = source.toMap()
    println(fresh)

    val destination = mutableMapOf("existing" to 0, "first" to -1)
    val returned: MutableMap<String, Int> = source.toMap(destination)
    println(returned === destination)
    println(destination)

    val nullable: Map<String?, Int?> = sequenceOf(
        Pair<String?, Int?>(null, null),
        Pair<String?, Int?>("x", 1),
        Pair<String?, Int?>(null, 2)
    ).toMap()
    println(nullable)

    val emptyDestination = mutableMapOf("keep" to 7)
    emptySequence<Pair<String, Int>>().toMap(emptyDestination)
    println(emptyDestination)
}
