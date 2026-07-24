@file:Suppress("UNCHECKED_CAST")

package kotlin.collections

import kotlin.internal.KsSymbolName

// MIGRATION-COL-004
// List association / grouping / indexing / side-effect / unzip HOFs migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//
// These implementations reuse the List indexing path (this[i] / size) and the
// MutableMap / MutableList factory bridges in CollectionFactories.kt.
// withIndex constructs IndexedValue instances through the retained runtime helper
// kk_indexed_value_new so that property access / destructuring continues to work
// against the existing synthetic IndexedValue stub.

// --- associate variants ------------------------------------------------------

public fun <T, K, V> List<T>.associate(transform: (T) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    var i = 0
    while (i < size) {
        val pair = transform(this[i])
        result[pair.first] = pair.second
        i += 1
    }
    return result as Map<K, V>
}

public fun <T, K> List<T>.associateBy(keySelector: (T) -> K): Map<K, T> {
    val result = mutableMapOf<K, T>()
    var i = 0
    while (i < size) {
        val elem = this[i]
        result[keySelector(elem)] = elem
        i += 1
    }
    return result as Map<K, T>
}

public fun <T, K, V> List<T>.associateBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    var i = 0
    while (i < size) {
        val elem = this[i]
        result[keySelector(elem)] = valueTransform(elem)
        i += 1
    }
    return result as Map<K, V>
}

public fun <T, V> List<T>.associateWith(valueTransform: (T) -> V): Map<T, V> {
    val result = mutableMapOf<T, V>()
    var i = 0
    while (i < size) {
        val elem = this[i]
        result[elem] = valueTransform(elem)
        i += 1
    }
    return result as Map<T, V>
}

// --- associateTo variants ----------------------------------------------------

public fun <T, K, V, M : MutableMap<K, V>> List<T>.associateTo(
    destination: M,
    transform: (T) -> Pair<K, V>
): M {
    val dest: MutableMap<K, V> = destination
    var i = 0
    while (i < size) {
        val pair = transform(this[i])
        dest[pair.first] = pair.second
        i += 1
    }
    return destination
}

public fun <T, K, M : MutableMap<K, T>> List<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K
): M {
    val dest: MutableMap<K, T> = destination
    var i = 0
    while (i < size) {
        val elem = this[i]
        dest[keySelector(elem)] = elem
        i += 1
    }
    return destination
}

public fun <T, K, V, M : MutableMap<K, V>> List<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): M {
    val dest: MutableMap<K, V> = destination
    var i = 0
    while (i < size) {
        val elem = this[i]
        dest[keySelector(elem)] = valueTransform(elem)
        i += 1
    }
    return destination
}

public fun <T, V, M : MutableMap<T, V>> List<T>.associateWithTo(
    destination: M,
    valueTransform: (T) -> V
): M {
    val dest: MutableMap<T, V> = destination
    var i = 0
    while (i < size) {
        val elem = this[i]
        dest[elem] = valueTransform(elem)
        i += 1
    }
    return destination
}

// --- groupBy variants ------------------------------------------------------

public fun <T, K> List<T>.groupBy(keySelector: (T) -> K): Map<K, List<T>> {
    val result = mutableMapOf<K, MutableList<T>>()
    var i = 0
    while (i < size) {
        val elem = this[i]
        val key = keySelector(elem)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(elem)
            result[key] = bucket
        } else {
            existing.add(elem)
        }
        i += 1
    }
    return result as Map<K, List<T>>
}

public fun <T, K, V> List<T>.groupBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    var i = 0
    while (i < size) {
        val elem = this[i]
        val key = keySelector(elem)
        val value = valueTransform(elem)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(value)
            result[key] = bucket
        } else {
            existing.add(value)
        }
        i += 1
    }
    return result as Map<K, List<V>>
}

public fun <T, K, M : MutableMap<K, MutableList<T>>> List<T>.groupByTo(
    destination: M,
    keySelector: (T) -> K
): M {
    val dest: MutableMap<K, MutableList<T>> = destination
    var i = 0
    while (i < size) {
        val elem = this[i]
        val key = keySelector(elem)
        val existing = dest[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(elem)
            dest[key] = bucket
        } else {
            existing.add(elem)
        }
        i += 1
    }
    return destination
}

public fun <T, K, V, M : MutableMap<K, MutableList<V>>> List<T>.groupByTo(
    destination: M,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): M {
    val dest: MutableMap<K, MutableList<V>> = destination
    var i = 0
    while (i < size) {
        val elem = this[i]
        val key = keySelector(elem)
        val value = valueTransform(elem)
        val existing = dest[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(value)
            dest[key] = bucket
        } else {
            existing.add(value)
        }
        i += 1
    }
    return destination
}

// --- side effect / indexing ------------------------------------------------

public fun <T> List<T>.onEach(action: (T) -> Unit): List<T> {
    var i = 0
    while (i < size) {
        action(this[i])
        i += 1
    }
    return this
}

public fun <T> List<T>.onEachIndexed(action: (Int, T) -> Unit): List<T> {
    var i = 0
    while (i < size) {
        action(i, this[i])
        i += 1
    }
    return this
}

public fun <T> List<T>.partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> {
    val first = mutableListOf<T>()
    val second = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val elem = this[i]
        if (predicate(elem)) {
            first.add(elem)
        } else {
            second.add(elem)
        }
        i += 1
    }
    return Pair(first as List<T>, second as List<T>)
}

public fun <T, R> List<Pair<T, R>>.unzip(): Pair<List<T>, List<R>> {
    val first = mutableListOf<T>()
    val second = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val pair = this[i]
        first.add(pair.first)
        second.add(pair.second)
        i += 1
    }
    return Pair(first as List<T>, second as List<R>)
}

@KsSymbolName("kk_indexed_value_new")
private external fun <T> kk_indexed_value_new(index: Int, value: T): IndexedValue<T>

public fun <T> List<T>.withIndex(): Iterable<IndexedValue<T>> {
    val result = mutableListOf<IndexedValue<T>>()
    var i = 0
    while (i < size) {
        result.add(kk_indexed_value_new(i, this[i]))
        i += 1
    }
    return result
}

public fun <T> Iterable<T>.withIndex(): Iterable<IndexedValue<T>> {
    val list = this.toMutableList()
    val result = mutableListOf<IndexedValue<T>>()
    var i = 0
    while (i < list.size) {
        result.add(kk_indexed_value_new(i, list[i]))
        i += 1
    }
    return result
}
