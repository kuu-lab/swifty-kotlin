@file:kotlin.jvm.JvmName("MapsKt")

package kotlin.collections

public inline fun <K, V, R> Map<out K, V>.map(transform: (Map.Entry<K, V>) -> R): List<R> {
    val result = mutableListOf<R>()
    for (entry in this) {
        result.add(transform(entry))
    }
    return result
}

public inline fun <K, V> Map<out K, V>.filter(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry)) result[entry.key] = entry.value
    }
    return result
}
