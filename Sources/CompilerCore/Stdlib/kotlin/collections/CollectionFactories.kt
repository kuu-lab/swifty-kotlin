package kotlin.collections

import kotlin.internal.KsSymbolName

// MIGRATION-COL-001
// Collection factory functions.
// Migration source: Sources/Runtime/RuntimeCollections.swift, RuntimeSetAndMap.swift

// --- ABI bridges -------------------------------------------------------------
//
// These map directly to @_cdecl functions in RuntimeCollections.swift and
// RuntimeSetAndMap.swift. Each external declaration matches the Swift-side
// parameter layout: null array + count=0 produces a fresh mutable collection.

@KsSymbolName("__kk_emptyList")
private external fun <T> __kk_emptyList(): List<T>

@KsSymbolName("__kk_list_of")
private external fun <T> __kk_list_of(array: Any?, count: Int): MutableList<T>

@KsSymbolName("__kk_emptySet")
private external fun <T> __kk_emptySet(): Set<T>

@KsSymbolName("__kk_set_of")
private external fun <T> __kk_set_of(array: Any?, count: Int): MutableSet<T>

@KsSymbolName("__kk_emptyMap")
private external fun <K, V> __kk_emptyMap(): Map<K, V>

@KsSymbolName("__kk_map_of")
private external fun <K, V> __kk_map_of(keys: Any?, values: Any?, count: Int): MutableMap<K, V>

// --- emptyList / emptySet / emptyMap -----------------------------------------

public fun <T> emptyList(): List<T> = __kk_emptyList()

public fun <T> emptySet(): Set<T> = __kk_emptySet()

public fun <K, V> emptyMap(): Map<K, V> = __kk_emptyMap()

// --- List factories ----------------------------------------------------------

public fun <T> listOf(): List<T> = emptyList()

@SinceKotlin("1.9")
@Suppress("UNCHECKED_CAST")
public fun <T> listOf(element: T): List<T> {
    val result: MutableList<T> = __kk_list_of(null, 0)
    result.add(element)
    return result as List<T>
}

@Suppress("UNCHECKED_CAST")
public fun <T> listOf(vararg elements: T): List<T> {
    if (elements.size == 0) return emptyList<T>()
    val result: MutableList<T> = __kk_list_of(null, 0)
    for (element in elements) {
        result.add(element)
    }
    return result as List<T>
}

public fun <T> mutableListOf(): MutableList<T> = __kk_list_of(null, 0)

public fun <T> mutableListOf(vararg elements: T): MutableList<T> {
    val result: MutableList<T> = __kk_list_of(null, 0)
    for (element in elements) {
        result.add(element)
    }
    return result
}

public fun <T : Any> listOfNotNull(element: T?): List<T> =
    if (element != null) listOf(element) else emptyList()

public fun <T : Any> listOfNotNull(vararg elements: T?): List<T> {
    val result: MutableList<T> = __kk_list_of(null, 0)
    for (element in elements) {
        if (element != null) result.add(element)
    }
    return result
}

// --- Set factories -----------------------------------------------------------

public fun <T> setOf(): Set<T> = emptySet()

public fun <T> setOf(vararg elements: T): Set<T> {
    if (elements.size == 0) return emptySet<T>()
    val result: MutableSet<T> = __kk_set_of(null, 0)
    for (element in elements) {
        result.add(element)
    }
    return result
}

public fun <T> mutableSetOf(): MutableSet<T> = __kk_set_of(null, 0)

public fun <T> mutableSetOf(vararg elements: T): MutableSet<T> {
    val result: MutableSet<T> = __kk_set_of(null, 0)
    for (element in elements) {
        result.add(element)
    }
    return result
}

// --- Map factories -----------------------------------------------------------

public fun <K, V> mapOf(): Map<K, V> = emptyMap()

/**
 * Returns a new read-only map containing only the specified key-value pair.
 *
 * Keep this overload distinct from the vararg overload so overload resolution
 * matches the Kotlin stdlib API while reusing the shared map runtime path.
 */
@Suppress("UNCHECKED_CAST")
public fun <K, V> mapOf(pair: Pair<K, V>): Map<K, V> {
    val result: MutableMap<K, V> = __kk_map_of(null, null, 1)
    result[pair.first] = pair.second
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> mapOf(vararg pairs: Pair<K, V>): Map<K, V> {
    if (pairs.size == 0) return emptyMap<K, V>()
    val result: MutableMap<K, V> = __kk_map_of(null, null, 0)
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result as Map<K, V>
}

@PublishedApi
internal fun mapCapacity(expectedSize: Int): Int = when {
    expectedSize < 0 -> expectedSize
    expectedSize < 3 -> expectedSize + 1
    expectedSize < (1 shl 30) -> ((expectedSize / 0.75F) + 1.0F).toInt()
    else -> Int.MAX_VALUE
}

public fun <K, V> mutableMapOf(): MutableMap<K, V> = __kk_map_of(null, null, 0)

public fun <K, V> mutableMapOf(vararg pairs: Pair<K, V>): MutableMap<K, V> {
    val result: MutableMap<K, V> = __kk_map_of(null, null, 0)
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result
}
