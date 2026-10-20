package kotlin.collections

import kotlin.sequences.asIterable

import kotlin.jvm.internal.__jvmNewMap
import kotlin.jvm.internal.__jvmSingletonMap

public fun <K, V> emptyMap(): Map<K, V> = RepositoryEmptyMap as Map<K, V>
public fun <K, V> mapOf(pair: Pair<K, V>): Map<K, V> = __jvmSingletonMap(pair.first, pair.second)
public fun <K, V> mapOf(vararg pairs: Pair<K, V>): Map<K, V> {
    if (pairs.size == 0) return emptyMap<K, V>()
    val result = __jvmNewMap<K, V>()
    for (pair in pairs) result[pair.first] = pair.second
    return result
}
public fun <K, V> mutableMapOf(vararg pairs: Pair<K, V>): MutableMap<K, V> {
    val result = __jvmNewMap<K, V>()
    for (pair in pairs) result[pair.first] = pair.second
    return result
}

public inline operator fun <K, V> MutableMap<K, V>.set(key: K, value: V) { this.put(key, value) }

public inline operator fun <K, V> Map<K, V>.contains(key: K): Boolean = this.containsKey(key)


public fun <K, V> Iterable<Pair<K, V>>.toMap(): Map<K, V> {
    if (this is Collection<*>) {
        if (this.size == 0) return emptyMap<K, V>()
        if (this.size == 1) {
            val pair = if (this is List<*>) this[0] as Pair<K, V> else this.iterator().next()
            return mapOf(pair)
        }
    }
    val result = mutableMapOf<K, V>()
    var lastPair: Pair<K, V>? = null
    for (pair in this) { result[pair.first] = pair.second; lastPair = pair }
    if (this is Collection<*>) return result
    if (result.size == 0) return emptyMap<K, V>()
    if (result.size == 1) return mapOf(Pair(result.keys.iterator().next(), lastPair!!.second))
    return result
}

public fun <K, V> kotlin.sequences.Sequence<Pair<K, V>>.toMap(): Map<K, V> = this.asIterable().toMap()

fun mapCapacity(expectedSize: Int): Int = if (expectedSize < 0) expectedSize else if (expectedSize < 3) expectedSize + 1 else if (expectedSize < 1073741824) (expectedSize.toFloat() / 0.75f + 1.0f).toInt() else Int.MAX_VALUE

private fun <K, V> optimizeOperatorMap(result: MutableMap<K, V>): Map<K, V> {
    if (result.size == 0) return emptyMap<K, V>()
    if (result.size == 1) {
        val key = result.keys.iterator().next()
        return mapOf(Pair(key, result[key] as V))
    }
    return result
}

public operator fun <K, V> Map<out K, V>.minus(key: K): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (current in this.keys) {
        // The key exists in this map; its value may legitimately be null.
        if (current != key) result[current] = this[current] as V
    }
    return optimizeOperatorMap(result)
}
public operator fun <K, V> Map<out K, V>.minus(keys: Iterable<K>): Map<K, V> {
    val removed = mutableSetOf<K>()
    for (key in keys) removed.add(key)
    val result = mutableMapOf<K, V>()
    for (current in this.keys) {
        if (!removed.contains(current)) result[current] = this[current] as V
    }
    return optimizeOperatorMap(result)
}
public operator fun <K, V> Map<out K, V>.plus(pair: Pair<K, V>): Map<K, V> {
    if (this.size == 0) return mapOf(pair)
    val result = mutableMapOf<K, V>()
    for (key in this.keys) result[key] = this[key] as V
    result[pair.first] = pair.second
    return result
}
public operator fun <K, V> Map<out K, V>.plus(map: Map<out K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (key in this.keys) result[key] = this[key] as V
    for (key in map.keys) result[key] = map[key] as V
    return result
}
