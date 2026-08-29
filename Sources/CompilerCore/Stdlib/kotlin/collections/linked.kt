package kotlin.collections

// KSP-954: Linked collection factories are source-backed declarations. Their
// call sites still use the shared collection-factory lowering path so the
// runtime preserves mutability, deduplication, overwrite, and insertion order.

public fun <T> linkedSetOf(): LinkedHashSet<T> = LinkedHashSet()

public fun <T> linkedSetOf(vararg elements: T): LinkedHashSet<T> {
    val result = LinkedHashSet<T>(elements.size)
    for (element in elements) {
        result.add(element)
    }
    return result
}

public fun <K, V> linkedMapOf(): LinkedHashMap<K, V> = LinkedHashMap()

public fun <K, V> linkedMapOf(vararg pairs: Pair<K, V>): LinkedHashMap<K, V> {
    val result = LinkedHashMap<K, V>(pairs.size)
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result
}
