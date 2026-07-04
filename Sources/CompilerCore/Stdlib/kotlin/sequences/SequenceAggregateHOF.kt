package kotlin.collections

// MIGRATION-SEQ-004
// Sequence aggregate HOFs migrated to Kotlin source.
// Placed in kotlin.collections package for Map/MutableMap/List/MutableList resolution.
// Uses "for in" iteration to avoid polluting toList() overload resolution
// (this.toList() in kotlin.collections would make Collection.toList() resolve to
// kk_sequence_to_list instead of kk_collection_toList in Sema dispatch).
//
// Migration source:
//   Sources/Runtime/RuntimeSequence.swift
//   Sources/Runtime/RuntimeSequenceAssociation.swift
//   Sources/Runtime/RuntimeSequenceFoldScan.swift
//
// Migrated: fold, reduce, scan, sumOf, maxByOrNull, minByOrNull,
//           associate, associateBy, groupBy
// scan/fold/reduce still resolve to runtime ABI stubs at call sites until
// source-backed iteration parity is complete (see MIGRATION-SEQ-004b notes).

public fun <T, R> Sequence<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    for (elem in this) {
        accumulator = operation(accumulator, elem)
    }
    return accumulator
}

public fun <T> Sequence<T>.reduce(operation: (T, T) -> T): T {
    var accumulator: T? = null
    var first = true
    for (elem in this) {
        if (first) { accumulator = elem; first = false }
        else { accumulator = operation(accumulator!!, elem) }
    }
    if (first) throw UnsupportedOperationException("Empty sequence can't be reduced.")
    return accumulator!!
}

public fun <T, R> Sequence<T>.scan(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    for (elem in this) {
        accumulator = operation(accumulator, elem)
        result.add(accumulator)
    }
    return result
}

// Sema exposes the public call result as Map<K, V>; the source body returns the
// mutable implementation type to avoid current MutableMap-to-Map coercion noise.
public fun <T, K, V> Sequence<T>.associate(transform: (T) -> Pair<K, V>): MutableMap<K, V> {
    val result = mutableMapOf<K, V>()
    for (elem in this) {
        val pair = transform(elem)
        result[pair.first] = pair.second
    }
    return result
}

public fun <T, K> Sequence<T>.associateBy(keySelector: (T) -> K): MutableMap<K, T> {
    val result = mutableMapOf<K, T>()
    for (elem in this) {
        result[keySelector(elem)] = elem
    }
    return result
}

public fun <T, K, V> Sequence<T>.associateBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): MutableMap<K, V> {
    val result = mutableMapOf<K, V>()
    for (elem in this) {
        result[keySelector(elem)] = valueTransform(elem)
    }
    return result
}

public fun <T, K> Sequence<T>.groupBy(keySelector: (T) -> K): MutableMap<K, MutableList<T>> {
    val result = mutableMapOf<K, MutableList<T>>()
    for (elem in this) {
        val key = keySelector(elem)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(elem)
            result[key] = bucket
        } else {
            existing.add(elem)
        }
    }
    return result
}

public fun <T, K, V> Sequence<T>.groupBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): MutableMap<K, MutableList<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (elem in this) {
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
    }
    return result
}

public fun <T> Sequence<T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    for (elem in this) { sum += selector(elem) }
    return sum
}

public fun <T, R : Comparable<R>> Sequence<T>.maxByOrNull(selector: (T) -> R): T? {
    var bestElem: T? = null
    var bestKey: R? = null
    for (elem in this) {
        val key = selector(elem)
        if (bestKey == null || key > bestKey!!) { bestElem = elem; bestKey = key }
    }
    return bestElem
}

public fun <T, R : Comparable<R>> Sequence<T>.minByOrNull(selector: (T) -> R): T? {
    var bestElem: T? = null
    var bestKey: R? = null
    for (elem in this) {
        val key = selector(elem)
        if (bestKey == null || key < bestKey!!) { bestElem = elem; bestKey = key }
    }
    return bestElem
}
