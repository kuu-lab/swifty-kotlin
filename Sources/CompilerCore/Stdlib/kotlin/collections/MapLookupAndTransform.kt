package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-431: Map's four runtime-backed property links and MutableMap's mutation
// links are registered as direct residual ABI members because built-in map
// boxes bypass itable registration (isEmpty/get use direct @KsSymbolName
// bridges in Map/Map.kt). The residual Map.Entry shell keeps the runtime
// key/value accessors available until nested source declarations can be
// collected in the same pass. The entry bridge tags each entry with the
// runtime map-entry type so `toString` prints `k=v`; the `withDefault` state
// remains stored on the runtime map box (`__kk_map_withDefault` /
// `__kk_map_has_default` / `__kk_map_implicit_default`).

@KsSymbolName("__kk_map_withDefault")
private external fun <K, V> __kk_map_withDefault(map: Map<K, V>, defaultValue: (K) -> V): Map<K, V>

@KsSymbolName("__kk_map_implicit_default")
private external fun <K, V> __kk_map_implicit_default(map: Map<K, V>, key: K): V?

@KsSymbolName("__kk_map_has_default")
private external fun <K, V> __kk_map_has_default(map: Map<K, V>): Boolean

@Suppress("UNCHECKED_CAST")
public inline operator fun <@kotlin.internal.OnlyInputTypes K, V> Map<out K, V>.get(key: K): V? =
    (this as Map<K, V>).get(key)

@KsSymbolName("__kk_mutable_map_iterator")
@PublishedApi
internal external fun <K, V> __kk_mutable_map_iterator(
    map: MutableMap<K, V>
): MutableIterator<MutableMap.MutableEntry<K, V>>

@KsSymbolName("__kk_mutable_map_withDefault")
private external fun <K, V> __kk_mutable_map_withDefault(
    map: MutableMap<K, V>,
    defaultValue: (K) -> V
): MutableMap<K, V>

@KsSymbolName("__kk_mutable_map_remove")
@PublishedApi
internal external fun <K, V> __kk_mutable_map_remove(map: MutableMap<K, V>, key: K): V?

// Kotlin 2.3.10 defines Map.contains as the key-membership operator.
public inline operator fun <K, V> Map<out K, V>.contains(key: K): Boolean = containsKey(key)

public fun <K, V> Map<K, V>.containsKey(key: K): Boolean = keys.contains(key)

public fun <K, V> Map<K, V>.containsValue(value: V): Boolean = values.contains(value)

@PublishedApi
internal fun <K, V> Map<K, V>.getOrImplicitDefault(key: K): V {
    for (entry in this.entries) {
        if (entry.key == key) return entry.value
    }
    if (__kk_map_has_default(this)) {
        @Suppress("UNCHECKED_CAST")
        return __kk_map_implicit_default(this, key) as V
    }
    throw NoSuchElementException("Key $key is missing in the map.")
}

public fun <K, V> Map<K, V>.getValue(key: K): V = getOrImplicitDefault(key)

public fun <K, V> Map<K, V>.getOrDefault(key: K, defaultValue: V): V {
    for (entry in this.entries) {
        if (entry.key == key) return entry.value
    }
    return defaultValue
}

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

public inline fun <K, V> MutableMap<K, V>.computeIfAbsent(key: K, mappingFunction: (K) -> V): V {
    val value = this[key]
    if (value != null) return value
    val computedValue = mappingFunction(key)
    if (computedValue != null) this[key] = computedValue
    return computedValue
}

public fun <K, V> MutableMap<K, V>.computeIfPresent(
    key: K,
    remappingFunction: (K, V) -> V?
): V? {
    val oldValue = this[key] ?: return null
    val newValue = remappingFunction(key, oldValue)
    if (newValue == null) remove(key) else this[key] = newValue
    return newValue
}

public fun <K, V> MutableMap<K, V>.putIfAbsent(key: K, value: V): V? {
    val oldValue = this[key]
    if (oldValue != null) return oldValue
    return put(key, value)
}

public fun <K, V> MutableMap<K, V>.merge(
    key: K,
    value: V,
    remappingFunction: (V, V) -> V?
): V? {
    if (value == null) throw NullPointerException()
    val oldValue = this[key]
    val newValue = if (oldValue == null) value else remappingFunction(oldValue, value)
    if (newValue == null) remove(key) else this[key] = newValue
    return newValue
}

public inline fun <K, V> MutableMap<out K, V>.remove(key: K): V? {
    return __kk_mutable_map_remove(this, key)
}

@SinceKotlin("1.1")
@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public fun <K, V> MutableMap<out K, out V>.remove(key: K, value: V): Boolean {
    val map = this as MutableMap<K, V>
    val current = map[key]
    if (current != value || (current == null && !map.containsKey(key))) return false
    map.remove(key)
    return true
}

public inline operator fun <K, V> MutableMap<K, V>.iterator(): MutableIterator<MutableMap.MutableEntry<K, V>> =
    __kk_mutable_map_iterator(this)

public inline operator fun <K, V> MutableMap<K, V>.minusAssign(key: K) {
    remove(key)
}

public inline operator fun <K, V> MutableMap<K, V>.minusAssign(keys: Iterable<K>) {
    for (key in keys) remove(key)
}

public inline operator fun <K, V> MutableMap<K, V>.minusAssign(keys: Sequence<K>) {
    for (key in keys) remove(key)
}

public inline operator fun <K, V> MutableMap<K, V>.minusAssign(keys: Array<out K>) {
    for (key in keys) remove(key)
}

public inline operator fun <K, V> MutableMap<in K, in V>.plusAssign(pair: Pair<K, V>) {
    put(pair.first, pair.second)
}

public inline operator fun <K, V> MutableMap<in K, in V>.plusAssign(pairs: Iterable<Pair<K, V>>) {
    for (pair in pairs) put(pair.first, pair.second)
}

public inline operator fun <K, V> MutableMap<in K, in V>.plusAssign(pairs: Sequence<Pair<K, V>>) {
    for (pair in pairs) put(pair.first, pair.second)
}

public inline operator fun <K, V> MutableMap<in K, in V>.plusAssign(pairs: Array<out Pair<K, V>>) {
    for (pair in pairs) put(pair.first, pair.second)
}

public inline operator fun <K, V> MutableMap<in K, in V>.plusAssign(map: Map<K, V>) {
    for (entry in map.entries) put(entry.key, entry.value)
}

public fun <K, V> MutableMap<in K, in V>.putAll(pairs: Iterable<Pair<K, V>>): Unit {
    for (pair in pairs) put(pair.first, pair.second)
}

public fun <K, V> MutableMap<in K, in V>.putAll(pairs: Sequence<Pair<K, V>>): Unit {
    for (pair in pairs) put(pair.first, pair.second)
}

public fun <K, V> MutableMap<in K, in V>.putAll(pairs: Array<out Pair<K, V>>): Unit {
    for (pair in pairs) put(pair.first, pair.second)
}

public inline operator fun <K, V> MutableMap<K, V>.set(key: K, value: V) {
    put(key, value)
}

public fun <K, V> Map<K, V>.toList(): List<Pair<K, V>> {
    val result = mutableListOf<Pair<K, V>>()
    for (entry in this.entries) {
        result.add(Pair(entry.key, entry.value))
    }
    return result
}

public fun <K, V> Map<K, V>.toMutableMap(): MutableMap<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> Map<out K, V>.toMap(): Map<K, V> {
    if (this.size == 0) return emptyMap<K, V>()
    if (this.size == 1) {
        for (entry in this.entries) {
            return mapOf(Pair(entry.key, entry.value))
        }
    }
    val typedSource = this as Map<K, V>
    val copy = typedSource.toMutableMap() as Map<K, V>
    return copy
}

@SinceKotlin("1.1")
@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public fun <K, V, C : MutableMap<in K, in V>> Map<out K, V>.toMap(destination: C): C {
    val typedSource = this as Map<K, V>
    val typedDestination = destination as MutableMap<K, V>
    typedDestination.putAll(typedSource)
    return destination
}

public fun <K, V> Map<K, V>?.orEmpty(): Map<K, V> {
    if (this == null) return emptyMap<K, V>()
    return this!!
}

// KUU-1361: JVM `Map.toSortedMap` returns `java.util.SortedMap`.
public fun <K : Comparable<K>, V> Map<out K, V>.toSortedMap(): java.util.SortedMap<K, V> {
    val result = java.util.TreeMap<K, V>()
    result.putAll(this)
    return result
}

public fun <K, V> Map<out K, V>.toSortedMap(comparator: Comparator<in K>): java.util.SortedMap<K, V> {
    val result = java.util.TreeMap<K, V>(comparator)
    result.putAll(this)
    return result
}

public fun <K, V> Map<K, V>.withDefault(defaultValue: (K) -> V): Map<K, V> =
    __kk_map_withDefault(this, defaultValue)

public fun <K, V> MutableMap<K, V>.withDefault(defaultValue: (K) -> V): MutableMap<K, V> =
    __kk_mutable_map_withDefault(this, defaultValue)
