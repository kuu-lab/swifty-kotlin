fun <K, V> genericPick(map: Map<K, V>): String? {
    return map.firstNotNullOfOrNull { entry ->
        if (entry.value != null) entry.value.toString() else null
    }
}

fun main() {
    val ordered = linkedMapOf("skip" to 1, "hit" to 2, "tail" to 3)
    var calls = 0
    val first = ordered.firstNotNullOf<String, Int, String> { entry ->
        calls += 1
        if (entry.key == "hit") "${entry.key}:${entry.value}" else null
    }
    println(first)
    println(calls)

    val nullable: Map<String?, Int?> = linkedMapOf(null to null, "value" to null, "last" to 3)
    println(nullable.firstNotNullOfOrNull<String?, Int?, String> { entry -> entry.key ?: "null-key" })
    println(nullable.firstNotNullOfOrNull<String?, Int?, String> { entry -> entry.value?.toString() })
    println(genericPick(nullable))

    val allNull = mapOf("a" to 1, "b" to 2)
    println(allNull.firstNotNullOfOrNull<String, Int, String> { null })

    try {
        emptyMap<String, Int>().firstNotNullOf<String, Int, String> { "unexpected" }
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    try {
        allNull.firstNotNullOf<String, Int, String> { null }
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    try {
        ordered.firstNotNullOf<String, Int, String> { throw IllegalStateException("transform failed") }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
