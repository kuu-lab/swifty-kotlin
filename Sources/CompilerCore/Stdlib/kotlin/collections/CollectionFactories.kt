package kotlin.collections

import kotlin.internal.KsSymbolName

// MIGRATION-COL-001
// Collection factory functions.
// Migration source: Sources/Runtime/RuntimeCollections.swift, RuntimeSetAndMap.swift
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// CollectionLiteralLoweringPass still intercepts all factory call sites and
// rewrites them to kk_* ABI calls. This file is the migration target; wiring
// (and removal of sema stubs STDLIB-410) happens in RF-STDLIB-004+.

// ─── ABI bridges ─────────────────────────────────────────────────────────────
//
// These map directly to @_cdecl functions in RuntimeCollections.swift and
// RuntimeSetAndMap.swift. Each external declaration matches the Swift-side
// parameter layout: null array + count=0 produces a fresh mutable collection.

@KsSymbolName("kk_emptyList")
private external fun kk_emptyList(): List<Nothing>

@KsSymbolName("kk_list_of")
private external fun kk_list_of(array: Any?, count: Int): MutableList<Any?>

@KsSymbolName("kk_emptySet")
private external fun kk_emptySet(): Set<Nothing>

@KsSymbolName("kk_set_of")
private external fun kk_set_of(array: Any?, count: Int): MutableSet<Any?>

@KsSymbolName("kk_emptyMap")
private external fun kk_emptyMap(): Map<Nothing, Nothing>

@KsSymbolName("kk_map_of")
private external fun kk_map_of(keys: Any?, values: Any?, count: Int): MutableMap<Any?, Any?>

// ─── emptyList / emptySet / emptyMap ─────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T> emptyList(): List<T> = kk_emptyList() as List<T>

@Suppress("UNCHECKED_CAST")
public fun <T> emptySet(): Set<T> = kk_emptySet() as Set<T>

@Suppress("UNCHECKED_CAST")
public fun <K, V> emptyMap(): Map<K, V> = kk_emptyMap() as Map<K, V>

// ─── List factories ──────────────────────────────────────────────────────────

public fun <T> listOf(): List<T> = emptyList()

public fun <T> listOf(vararg elements: T): List<T> {
    if (elements.size == 0) return emptyList()
    val result = mutableListOf<T>()
    var i = 0
    while (i < elements.size) {
        result.add(elements[i])
        i++
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <T> mutableListOf(): MutableList<T> = kk_list_of(null, 0) as MutableList<T>

public fun <T> mutableListOf(vararg elements: T): MutableList<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < elements.size) {
        result.add(elements[i])
        i++
    }
    return result
}

// ─── Set factories ───────────────────────────────────────────────────────────

public fun <T> setOf(): Set<T> = emptySet()

public fun <T> setOf(vararg elements: T): Set<T> {
    if (elements.size == 0) return emptySet()
    val result = mutableSetOf<T>()
    var i = 0
    while (i < elements.size) {
        result.add(elements[i])
        i++
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <T> mutableSetOf(): MutableSet<T> = kk_set_of(null, 0) as MutableSet<T>

public fun <T> mutableSetOf(vararg elements: T): MutableSet<T> {
    val result = mutableSetOf<T>()
    var i = 0
    while (i < elements.size) {
        result.add(elements[i])
        i++
    }
    return result
}

// ─── Map factories ───────────────────────────────────────────────────────────

public fun <K, V> mapOf(): Map<K, V> = emptyMap()

public fun <K, V> mapOf(vararg pairs: Pair<K, V>): Map<K, V> {
    if (pairs.size == 0) return emptyMap()
    val result = mutableMapOf<K, V>()
    var i = 0
    while (i < pairs.size) {
        result[pairs[i].first] = pairs[i].second
        i++
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> mutableMapOf(): MutableMap<K, V> = kk_map_of(null, null, 0) as MutableMap<K, V>

public fun <K, V> mutableMapOf(vararg pairs: Pair<K, V>): MutableMap<K, V> {
    val result = mutableMapOf<K, V>()
    var i = 0
    while (i < pairs.size) {
        result[pairs[i].first] = pairs[i].second
        i++
    }
    return result
}
