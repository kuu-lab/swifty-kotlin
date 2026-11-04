fun main() {
    // KUU-3907: a capacity-only constructor destination left the element type
    // parameter unfixed; the `C : MutableCollection<in T>` bound must steer it
    // to the concrete ArrayList<String> rather than a stale type variable.
    val list = listOf("a", "bb").filterTo(ArrayList(1)) { it.isNotEmpty() }
    val typed: ArrayList<String> = list
    println(typed)

    val mutable: MutableList<String> = listOf("x").filterTo(ArrayList(2)) { true }
    println(mutable)

    // ktor-utils StringValues.kt shape: destination stored through MutableMap.set.
    val values = mutableMapOf<String, MutableList<String>>()
    for (entry in mapOf("k" to listOf("v1", "v2")).entries) {
        val kept = entry.value.filterTo(ArrayList(entry.value.size)) { it.isNotEmpty() }
        values[entry.key] = kept
    }
    println(values)

    // Other receivers and HOFs sharing the `C : MutableCollection<in T>` bound.
    println(sequenceOf(1, 2, 3).filterTo(ArrayList(2)) { it > 1 })
    println(arrayOf("p", "q").mapTo(ArrayList(2)) { it + it })
    println(listOf("a", null, "b").filterNotNullTo(ArrayList(3)))
    println(listOf(5, 6).filterNotTo(ArrayList(1)) { it > 5 })
}
