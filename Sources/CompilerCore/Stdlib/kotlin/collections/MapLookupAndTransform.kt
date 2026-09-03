package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.reflect.KProperty

// KSP-431
// Map lookup and conversion members migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSetAndMap.swift (kk_map_getValue,
// kk_map_getOrDefault, kk_map_contains_key, kk_map_contains_value, kk_map_keys,
// kk_map_values, kk_map_entries, kk_map_to_mutable_map, kk_map_withDefault),
// RuntimeCollectionHOF.swift (kk_map_getOrElse, kk_mutable_map_getOrPut,
// kk_map_toList) and RuntimeCollections.swift (kk_map_orEmpty).
//
// Remaining bridges: key lookup (`__kk_map_get`, exposed as the synthetic
// `Map.get` operator), entry materialization (`__kk_map_entries`, which tags
// each entry with the runtime map-entry type so `toString` prints `k=v`) and
// the `withDefault` state stored on the runtime map box
// (`__kk_map_withDefault` / `__kk_map_has_default` / `__kk_map_implicit_default`).
//
// `keys` / `values` / `entries` are declared as zero-argument functions rather
// than extension properties because this compiler's parser rejects a type
// parameter list on an extension property (`val <K, V> Map<K, V>.keys`); member
// access without parentheses resolves to them all the same.

@KsSymbolName("__kk_map_entries")
private external fun <K, V> __kk_map_entries(map: Map<K, V>): Set<Map.Entry<K, V>>

@KsSymbolName("__kk_map_withDefault")
private external fun <K, V> __kk_map_withDefault(map: Map<K, V>, defaultValue: (K) -> V): Map<K, V>

@KsSymbolName("__kk_map_implicit_default")
private external fun <K, V> __kk_map_implicit_default(map: Map<K, V>, key: K): V?

@KsSymbolName("__kk_map_has_default")
private external fun <K, V> __kk_map_has_default(map: Map<K, V>): Boolean

@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<out K, V>.get(key: K): V? =
    (this as Map<K, V>).get(key)

public fun <K, V> Map<K, V>.entries(): Set<Map.Entry<K, V>> = __kk_map_entries(this)

public fun <K, V> Map<K, V>.keys(): Set<K> {
    val result = mutableSetOf<K>()
    for (entry in this.entries) {
        result.add(entry.key)
    }
    return result
}

public fun <K, V> Map<K, V>.values(): Collection<V> {
    val result = mutableListOf<V>()
    for (entry in this.entries) {
        result.add(entry.value)
    }
    return result
}

// Kotlin 2.3.10 defines Map.contains as the key-membership operator.
public inline operator fun <K, V> Map<out K, V>.contains(key: K): Boolean = containsKey(key)

public fun <K, V> Map<K, V>.containsKey(key: K): Boolean {
    for (entry in this.entries) {
        if (entry.key == key) return true
    }
    return false
}

public fun <K, V> Map<K, V>.containsValue(value: V): Boolean {
    for (entry in this.entries) {
        if (entry.value == value) return true
    }
    return false
}

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

public inline operator fun <V, V1 : V> Map<in String, V>.getValue(
    thisRef: Any?,
    property: KProperty<*>
): V1 {
    @Suppress("UNCHECKED_CAST")
    return getOrImplicitDefault(property.name) as V1
}

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

public fun <K, V> Map<K, V>.withDefault(defaultValue: (K) -> V): Map<K, V> =
    __kk_map_withDefault(this, defaultValue)
