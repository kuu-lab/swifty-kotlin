package kotlin.collections

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
