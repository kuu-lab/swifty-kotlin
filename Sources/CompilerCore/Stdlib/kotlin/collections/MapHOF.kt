package kotlin.collections

import kotlin.internal.__valuesEqual

// MIGRATION-COL-015
// Map higher-order functions migrated from Swift Runtime
// Sources/Runtime/RuntimeCollectionHOF.swift (kk_map_* HOFs)
// Sources/Runtime/RuntimeSetAndMap.swift (kk_map_plus / kk_map_minus)

/**
 * Performs the given [action] on each entry.
 */
public inline fun <K, V> Map<K, V>.forEach(action: (Map.Entry<K, V>) -> Unit) {
    for (entry in this.entries) {
        action(entry)
    }
}

/**
 * Returns `true` if at least one entry matches the given [predicate].
 */
public inline fun <K, V> Map<K, V>.any(predicate: (Map.Entry<K, V>) -> Boolean): Boolean {
    for (entry in this.entries) {
        if (predicate(entry)) return true
    }
    return false
}

/**
 * Returns `true` if all entries match the given [predicate].
 */
public inline fun <K, V> Map<K, V>.all(predicate: (Map.Entry<K, V>) -> Boolean): Boolean {
    for (entry in this.entries) {
        if (!predicate(entry)) return false
    }
    return true
}

/**
 * Returns `true` if no entries match the given [predicate].
 */
public inline fun <K, V> Map<K, V>.none(predicate: (Map.Entry<K, V>) -> Boolean): Boolean {
    for (entry in this.entries) {
        if (predicate(entry)) return false
    }
    return true
}

/**
 * Returns the number of entries matching the given [predicate].
 */
public inline fun <K, V> Map<K, V>.count(predicate: (Map.Entry<K, V>) -> Boolean): Int {
    var count = 0
    for (entry in this.entries) {
        if (predicate(entry)) count++
    }
    return count
}

/**
 * Returns a list containing the results of applying the given [transform] function
 * to each entry in the original map.
 */
public inline fun <K, V, R> Map<K, V>.map(transform: (Map.Entry<K, V>) -> R): List<R> {
    val result = mutableListOf<R>()
    for (entry in this.entries) {
        result.add(transform(entry))
    }
    return result
}

/**
 * Returns a list containing only the non-null results of applying the given [transform] function
 * to each entry in the original map.
 */
public fun <K, V, R : Any> Map<K, V>.mapNotNull(transform: (Map.Entry<K, V>) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (entry in this.entries) {
        val value = transform(entry)
        if (value != null) result.add(value)
    }
    return result
}

/**
 * Returns a single list of all elements yielded from results of [transform] function
 * being invoked on each entry of the original map.
 */
public inline fun <K, V, R> Map<K, V>.flatMap(transform: (Map.Entry<K, V>) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (entry in this.entries) {
        for (element in transform(entry)) {
            result.add(element)
        }
    }
    return result
}

/**
 * Returns a map containing all entries matching the given [predicate].
 */
@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filter(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

/**
 * Returns a map containing all entries not matching the given [predicate].
 */
@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filterNot(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (!predicate(entry)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

/**
 * Returns a map containing all entries with keys matching the given [predicate].
 */
@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filterKeys(predicate: (K) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry.key)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

/**
 * Returns a map containing all entries with values matching the given [predicate].
 */
@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filterValues(predicate: (V) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry.value)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

/**
 * Returns a new map with entries having the keys obtained by applying the [transform] function
 * to each entry of the original map.
 */
@Suppress("UNCHECKED_CAST")
public inline fun <K, V, R> Map<K, V>.mapKeys(transform: (Map.Entry<K, V>) -> R): Map<R, V> {
    val result = mutableMapOf<R, V>()
    for (entry in this.entries) {
        result[transform(entry)] = entry.value
    }
    return result as Map<R, V>
}

/**
 * Returns a new map with entries having the values obtained by applying the [transform] function
 * to each entry of the original map.
 */
@Suppress("UNCHECKED_CAST")
public inline fun <K, V, R> Map<K, V>.mapValues(transform: (Map.Entry<K, V>) -> R): Map<K, R> {
    val result = mutableMapOf<K, R>()
    for (entry in this.entries) {
        result[entry.key] = transform(entry)
    }
    return result as Map<K, R>
}

/**
 * Populates the given [destination] map with entries having the keys obtained by applying
 * the [transform] function to each entry of the original map.
 */
public inline fun <K, V, R> Map<K, V>.mapKeysTo(
    destination: MutableMap<R, V>,
    transform: (Map.Entry<K, V>) -> R
): MutableMap<R, V> {
    for (entry in this.entries) {
        destination[transform(entry)] = entry.value
    }
    return destination
}

/**
 * Populates the given [destination] map with entries having the values obtained by applying
 * the [transform] function to each entry of the original map.
 */
public inline fun <K, V, R> Map<K, V>.mapValuesTo(
    destination: MutableMap<K, R>,
    transform: (Map.Entry<K, V>) -> R
): MutableMap<K, R> {
    for (entry in this.entries) {
        destination[entry.key] = transform(entry)
    }
    return destination
}

/**
 * Returns the first entry yielding the largest value of the given [selector] or `null`
 * if there are no entries.
 */
public inline fun <K, V, R : Comparable<R>> Map<K, V>.maxByOrNull(
    selector: (Map.Entry<K, V>) -> R
): Map.Entry<K, V>? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxEntry = iterator.next()
    var maxValue = selector(maxEntry)
    while (iterator.hasNext()) {
        val entry = iterator.next()
        val value = selector(entry)
        if (value > maxValue) {
            maxEntry = entry
            maxValue = value
        }
    }
    return maxEntry
}

/**
 * Returns the first entry yielding the smallest value of the given [selector] or `null`
 * if there are no entries.
 */
public inline fun <K, V, R : Comparable<R>> Map<K, V>.minByOrNull(
    selector: (Map.Entry<K, V>) -> R
): Map.Entry<K, V>? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var minEntry = iterator.next()
    var minValue = selector(minEntry)
    while (iterator.hasNext()) {
        val entry = iterator.next()
        val value = selector(entry)
        if (value < minValue) {
            minEntry = entry
            minValue = value
        }
    }
    return minEntry
}

/**
 * Returns a map containing all entries of the original map and the given [pair].
 */
@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.plus(pair: Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    result[pair.first] = pair.second
    return result as Map<K, V>
}

/**
 * Returns a map containing all entries of the original map and the given [map].
 */
@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.plus(map: Map<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    for (entry in map.entries) {
        result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

/**
 * Returns a map containing all entries of the original map except the entry with the given [key].
 */
@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.minus(key: K): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (entry.key != key) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

/**
 * Returns a map containing all entries of the original map except those with keys contained in [keys].
 */
@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.minus(keys: Iterable<K>): Map<K, V> {
    val keySet = mutableSetOf<K>()
    for (k in keys) keySet.add(k)
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (entry.key !in keySet) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

