package kotlin.collections

// MIGRATION-COL-007
// List グルーピング・関連付け HOF を Kotlin source に移行する
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// Sema stubs in HeaderHelpers+SyntheticListStubs.swift and
// HeaderHelpers+SyntheticListAggregateMembers.swift set external link
// names so all call sites dispatch directly to the corresponding
// kk_list_* runtime function. Bodies below are never executed.

// ─── groupBy ─────────────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T, K> Iterable<T>.groupBy(keySelector: (T) -> K): Map<K, List<T>> =
    mutableMapOf<K, MutableList<T>>() as Map<K, List<T>>  // kk_list_groupBy

@Suppress("UNCHECKED_CAST")
public fun <T, K, V> Iterable<T>.groupBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, List<V>> =
    mutableMapOf<K, MutableList<V>>() as Map<K, List<V>>  // kk_list_groupByTransform

public fun <T, K, M : MutableMap<in K, MutableList<T>>> Iterable<T>.groupByTo(
    destination: M,
    keySelector: (T) -> K
): M = destination  // kk_list_groupByTo

// ─── associate ───────────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T, K, V> Iterable<T>.associate(transform: (T) -> Pair<K, V>): Map<K, V> =
    mutableMapOf<K, V>()  // kk_list_associate

public fun <T, K, V, M : MutableMap<in K, in V>> Iterable<T>.associateTo(
    destination: M,
    transform: (T) -> Pair<K, V>
): M = destination  // kk_list_associateTo

// ─── associateBy ─────────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T, K> Iterable<T>.associateBy(keySelector: (T) -> K): Map<K, T> =
    mutableMapOf<K, T>()  // kk_list_associateBy

@Suppress("UNCHECKED_CAST")
public fun <T, K, V> Iterable<T>.associateBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, V> = mutableMapOf<K, V>()  // kk_list_associateByTransform

public fun <T, K, M : MutableMap<in K, in T>> Iterable<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K
): M = destination  // kk_list_associateByTo

// ─── associateWith ───────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <K, V> Iterable<K>.associateWith(valueSelector: (K) -> V): Map<K, V> =
    mutableMapOf<K, V>()  // kk_list_associateWith

public fun <K, V, M : MutableMap<in K, in V>> Iterable<K>.associateWithTo(
    destination: M,
    valueSelector: (K) -> V
): M = destination  // kk_list_associateWithTo

// ─── partition ───────────────────────────────────────────────────────────────

public fun <T> Iterable<T>.partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> =
    Pair(mutableListOf<T>(), mutableListOf<T>())  // kk_list_partition
