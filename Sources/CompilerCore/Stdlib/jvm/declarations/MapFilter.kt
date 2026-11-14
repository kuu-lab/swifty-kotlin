package kotlin.collections

public inline fun <K, V> Map<out K, V>.filter(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry)) result[entry.key] = entry.value
    }
    return result
}
