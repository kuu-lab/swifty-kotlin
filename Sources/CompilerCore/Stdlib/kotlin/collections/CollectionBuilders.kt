package kotlin.collections

import kotlin.internal.KsSymbolName

// MIGRATION-COL-011
// Builder DSL functions for collections.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticBuilderDSLStubs.swift

@KsSymbolName("__kk_builder_list_new")
private external fun <E> __kkBuilderListNew(capacity: Int): MutableList<E>

@KsSymbolName("__kk_builder_set_new")
private external fun <E> __kkBuilderSetNew(capacity: Int): MutableSet<E>

@KsSymbolName("__kk_builder_map_new")
private external fun <K, V> __kkBuilderMapNew(capacity: Int): MutableMap<K, V>

@KsSymbolName("__kk_builder_list_freeze")
private external fun <E> __kkBuilderListFreeze(value: MutableList<E>): List<E>

@KsSymbolName("__kk_builder_set_freeze")
private external fun <E> __kkBuilderSetFreeze(value: MutableSet<E>): Set<E>

@KsSymbolName("__kk_builder_map_freeze")
private external fun <K, V> __kkBuilderMapFreeze(value: MutableMap<K, V>): Map<K, V>

// The internal helpers mirror Kotlin stdlib's @PublishedApi entry points.
// Keep the builder action on a mutable receiver until the final freeze so an
// escaped receiver cannot mutate the returned read-only collection.

@PublishedApi
internal inline fun <E> buildListInternal(builderAction: MutableList<E>.() -> Unit): List<out E> {
    val result = __kkBuilderListNew<E>(0)
    result.builderAction()
    return __kkBuilderListFreeze(result)
}

@PublishedApi
internal inline fun <E> buildListInternal(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<out E> {
    require(capacity >= 0) { "capacity must be non-negative." }
    val result = __kkBuilderListNew<E>(capacity)
    result.builderAction()
    return __kkBuilderListFreeze(result)
}

@PublishedApi
internal inline fun <E> buildSetInternal(builderAction: MutableSet<E>.() -> Unit): Set<out E> {
    val result = __kkBuilderSetNew<E>(0)
    result.builderAction()
    return __kkBuilderSetFreeze(result)
}

@PublishedApi
internal inline fun <E> buildSetInternal(capacity: Int, builderAction: MutableSet<E>.() -> Unit): Set<out E> {
    require(capacity >= 0) { "capacity must be non-negative." }
    val result = __kkBuilderSetNew<E>(capacity)
    result.builderAction()
    return __kkBuilderSetFreeze(result)
}

@PublishedApi
internal inline fun <K, V> buildMapInternal(builderAction: MutableMap<K, V>.() -> Unit): Map<out K, out V> {
    val result = __kkBuilderMapNew<K, V>(0)
    result.builderAction()
    return __kkBuilderMapFreeze(result)
}

@PublishedApi
internal inline fun <K, V> buildMapInternal(capacity: Int, builderAction: MutableMap<K, V>.() -> Unit): Map<out K, out V> {
    require(capacity >= 0) { "capacity must be non-negative." }
    val result = __kkBuilderMapNew<K, V>(capacity)
    result.builderAction()
    return __kkBuilderMapFreeze(result)
}

// ─── buildList ────────────────────────────────────────────────────────────────

@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildList(builderAction: MutableList<E>.() -> Unit): List<out E> =
    buildListInternal(builderAction)

@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildList(capacity: Int, builderAction: MutableList<E>.() -> Unit): List<out E> =
    buildListInternal(capacity, builderAction)

// ─── buildSet ─────────────────────────────────────────────────────────────────

@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildSet(builderAction: MutableSet<E>.() -> Unit): Set<out E> =
    buildSetInternal(builderAction)

@kotlin.experimental.ExperimentalTypeInference
public inline fun <E> buildSet(capacity: Int, builderAction: MutableSet<E>.() -> Unit): Set<out E> =
    buildSetInternal(capacity, builderAction)

// ─── buildMap ─────────────────────────────────────────────────────────────────

@kotlin.experimental.ExperimentalTypeInference
public inline fun <K, V> buildMap(builderAction: MutableMap<K, V>.() -> Unit): Map<out K, out V> =
    buildMapInternal(builderAction)

@kotlin.experimental.ExperimentalTypeInference
public inline fun <K, V> buildMap(capacity: Int, builderAction: MutableMap<K, V>.() -> Unit): Map<out K, out V> =
    buildMapInternal(capacity, builderAction)
