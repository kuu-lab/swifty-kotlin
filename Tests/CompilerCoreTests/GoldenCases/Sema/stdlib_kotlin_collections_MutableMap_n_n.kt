// KUU-1597 Sema owner: pin MutableMap.MutableEntry-to-Map.Entry covariance, destructuring, and setValue resolution; values and mutation are exercised in Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_n_n.kt.
private fun <K, V> readOnly(entry: MutableMap.MutableEntry<K, V>): Map.Entry<K, V> = entry

private fun show(entry: MutableMap.MutableEntry<String, Int>): Pair<String, Int> {
    val wide: Map.Entry<Any, Any> = readOnly(entry)
    val (key, value) = entry
    return Pair(key, value)
}

fun main() {
    val map = mutableMapOf("key" to 1)
    val entry: MutableMap.MutableEntry<String, Int> = map.entries.iterator().next()
    val pair: Pair<String, Int> = show(entry)
    val previous: Int = entry.setValue(42)

    val nullableMap = mutableMapOf<String?, Int?>(null to null)
    val nullable: MutableMap.MutableEntry<String?, Int?> = nullableMap.entries.iterator().next()
    val nullableKey: String? = nullable.key
    val nullableValue: Int? = nullable.value
    val nullablePrevious: Int? = nullable.setValue(7)
}
