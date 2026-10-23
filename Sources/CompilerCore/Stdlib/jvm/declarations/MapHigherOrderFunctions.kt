package kotlin.collections

public inline fun <K, V> Map<K, V>.getOrElse(key: K, defaultValue: () -> V): V {
    val value = this[key]
    if (value != null) return value
    return defaultValue()
}

public inline fun <K, V> MutableMap<K, V>.getOrPut(key: K, defaultValue: () -> V): V {
    val value = this[key]
    if (value != null) return value

    val answer = defaultValue()
    this[key] = answer
    return answer
}

public inline fun <K, V> Map<K, V>.filterKeys(predicate: (K) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry.key)) result[entry.key] = entry.value
    }
    return result
}

public inline fun <K, V> Map<K, V>.filterValues(predicate: (V) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry.value)) result[entry.key] = entry.value
    }
    return result
}

public inline fun <K, V, R> Map<K, V>.mapKeys(transform: (Map.Entry<K, V>) -> R): Map<R, V> {
    val result = mutableMapOf<R, V>()
    for (entry in this.entries) {
        result[transform(entry)] = entry.value
    }
    return result
}

public inline fun <K, V, R> Map<K, V>.mapValues(transform: (Map.Entry<K, V>) -> R): Map<K, R> {
    val result = mutableMapOf<K, R>()
    for (entry in this.entries) {
        result[entry.key] = transform(entry)
    }
    return result
}
