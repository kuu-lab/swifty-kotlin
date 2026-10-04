package golden.sema

fun mapSingletonOverload(): Map<String?, Int?> {
    val nullablePair: Pair<String?, Int?> = Pair<String?, Int?>(null, null)
    val singleton = mapOf(nullablePair)
    val explicitSingleton = mapOf<String?, Int?>(Pair<String?, Int?>("key", 1))
    val vararg = mapOf(
        Pair<String?, Int?>(null, null),
        Pair<String?, Int?>("other", 2)
    )
    val entry = singleton.entries.first()
    val hash = singleton.hashCode()
    return if (singleton == mapOf(nullablePair) && vararg.size == 2 && explicitSingleton["key"] == 1 &&
        entry.key == null && entry.value == null && hash == singleton.hashCode()) singleton else mapOf()
}
