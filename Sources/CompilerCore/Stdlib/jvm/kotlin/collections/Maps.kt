package kotlin.collections

import kotlin.sequences.asIterable

import kotlin.jvm.internal.__jvmArrayList
import kotlin.jvm.internal.__jvmRemoveAllCollection
import kotlin.jvm.internal.__jvmNewMap
import kotlin.jvm.internal.__jvmCopyMap
import kotlin.jvm.internal.__jvmPutAllMap
import kotlin.jvm.internal.__jvmSingletonMap
import kotlin.jvm.internal.__jvmMapEntries
import kotlin.jvm.internal.__jvmMapEntryKey
import kotlin.jvm.internal.__jvmMapEntryValue

public operator fun <K, V> Map.Entry<K, V>.component1(): K = __jvmMapEntryKey(this) as K
public operator fun <K, V> Map.Entry<K, V>.component2(): V = __jvmMapEntryValue(this) as V

public fun <K, V> emptyMap(): Map<K, V> = RepositoryEmptyMap as Map<K, V>
public fun <K, V> mapOf(pair: Pair<K, V>): Map<K, V> = __jvmSingletonMap(pair.first, pair.second)
public fun <K, V> mapOf(vararg pairs: Pair<K, V>): Map<K, V> {
    if (pairs.size == 0) return emptyMap<K, V>()
    val result = __jvmNewMap<K, V>()
    for (pair in pairs) result.put(pair.first, pair.second)
    return result
}
public fun <K, V> mutableMapOf(vararg pairs: Pair<K, V>): MutableMap<K, V> {
    val result = __jvmNewMap<K, V>()
    for (pair in pairs) result.put(pair.first, pair.second)
    return result
}
public fun <K, V> linkedMapOf(vararg pairs: Pair<K, V>): java.util.LinkedHashMap<K, V> {
    val result = java.util.LinkedHashMap<K, V>()
    for (pair in pairs) result.put(pair.first, pair.second)
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

public fun <K, V> Map<out K, V>.toMutableMap(): MutableMap<K, V> = __jvmCopyMap(this)

@Suppress("UNCHECKED_CAST")
public fun <K, V> Map<out K, V>.toMap(): Map<K, V> {
    if (this.size == 0) return emptyMap<K, V>()
    if (this.size == 1) {
        val key = this.keys.iterator().next()
        return __jvmSingletonMap(key, this[key] as V)
    }
    return __jvmCopyMap(this)
}

public fun <K, V> sortedMapOf(vararg pairs: Pair<K, V>): java.util.SortedMap<K, V> {
    val result = java.util.TreeMap<K, V>()
    for (pair in pairs) result.put(pair.first, pair.second)
    return result
}

public fun <K, V> sortedMapOf(
    comparator: Comparator<in K>,
    vararg pairs: Pair<K, V>
): java.util.SortedMap<K, V> {
    val result = java.util.TreeMap<K, V>(comparator)
    for (pair in pairs) result.put(pair.first, pair.second)
    return result
}

public fun <K : Comparable<K>, V> Map<out K, V>.toSortedMap(): java.util.SortedMap<K, V> {
    val result = java.util.TreeMap<K, V>()
    __jvmPutAllMap(result, this)
    return result
}

public fun <K, V> Map<out K, V>.toSortedMap(comparator: Comparator<in K>): java.util.SortedMap<K, V> {
    val result = java.util.TreeMap<K, V>(comparator)
    __jvmPutAllMap(result, this)
    return result
}

fun mapCapacity(expectedSize: Int): Int = if (expectedSize < 0) expectedSize else if (expectedSize < 3) expectedSize + 1 else if (expectedSize < 1073741824) (expectedSize.toFloat() / 0.75f + 1.0f).toInt() else Int.MAX_VALUE

private fun <K, V> optimizeOperatorMap(result: MutableMap<K, V>): Map<K, V> {
    if (result.size == 0) return emptyMap<K, V>()
    if (result.size == 1) {
        val entry = __jvmMapEntries(result).iterator().next()
        return __jvmSingletonMap(__jvmMapEntryKey(entry) as K, __jvmMapEntryValue(entry) as V)
    }
    return result
}

public operator fun <K, V> Map<out K, V>.minus(key: K): Map<K, V> {
    val result = __jvmCopyMap(this)
    result.remove(key)
    return optimizeOperatorMap(result)
}
public operator fun <K, V> Map<out K, V>.minus(keys: Iterable<K>): Map<K, V> {
    val result = __jvmCopyMap(this)
    val removed = if (keys is Collection<*>) keys as Collection<K> else keys.toList()
    __jvmRemoveAllCollection(result.keys, removed)
    return optimizeOperatorMap(result)
}
public operator fun <K, V> Map<out K, V>.plus(pair: Pair<K, V>): Map<K, V> {
    if (this.size == 0) return mapOf(pair)
    val result = __jvmCopyMap(this)
    result[pair.first] = pair.second
    return result
}
public operator fun <K, V> Map<out K, V>.plus(map: Map<out K, V>): Map<K, V> {
    val result = __jvmCopyMap(this)
    __jvmPutAllMap(result, map)
    return result
}

public operator fun <K, V> Map<out K, V>.minus(keys: Array<out K>): Map<K, V> {
    val result = __jvmCopyMap(this)
    if (keys.size != 0) __jvmRemoveAllCollection(result.keys, __jvmArrayList(keys))
    return optimizeOperatorMap(result)
}

public operator fun <K, V> Map<out K, V>.minus(keys: kotlin.sequences.Sequence<K>): Map<K, V> {
    val result = __jvmCopyMap(this)
    val removed = keys.toList()
    if (!removed.isEmpty()) __jvmRemoveAllCollection(result.keys, removed)
    return optimizeOperatorMap(result)
}
