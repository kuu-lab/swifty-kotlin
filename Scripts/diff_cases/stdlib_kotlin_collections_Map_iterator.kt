private fun printEntries(map: Map<String?, Int?>) {
    val iterator = map.iterator()
    println(iterator.hasNext())
    while (iterator.hasNext()) {
        val entry = iterator.next()
        println("${entry.key}:${entry.value}")
    }
    println(iterator.hasNext())
}

fun main() {
    val empty = emptyMap<String?, Int?>()
    printEntries(empty)

    val single = mapOf<String?, Int?>(null to null)
    val first = single.iterator()
    val second = single.iterator()
    println(first !== second)
    printEntries(single)
    printEntries(single)

    val multiple = mapOf<String?, Int?>("a" to 1, "b" to null, null to 2)
    printEntries(multiple)

    @Suppress("UNCHECKED_CAST")
    val projected = mapOf<String?, Int?>("a" to 1, "b" to null, null to 2) as Map<Any?, Number?>
    val projectedEntry = projected.iterator().next()
    println("${projectedEntry.key}:${projectedEntry.value}")

    for ((key, value) in multiple) {
        println("$key:$value")
    }
}
