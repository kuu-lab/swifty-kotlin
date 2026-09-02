fun testSequenceToMapContracts(
    source: Sequence<Pair<String, Int>>,
    destination: MutableMap<Any?, Any?>
): Map<String, Int> {
    val fresh: Map<String, Int> = source.toMap()
    val returned: MutableMap<Any?, Any?> = source.toMap(destination)
    println(fresh)
    println(returned)
    return fresh
}
