package golden.sema

fun exerciseMapEntryMembers(values: Map<String, Int>): Pair<String, Int> {
    val entry = values.entries.first()
    val key = entry.component1()
    val value = entry.component2()
    return entry.toPair()
}
