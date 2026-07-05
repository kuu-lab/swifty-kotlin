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
// Implementations materialize through toList() before looping so they reuse the
// stable list indexing path instead of the still-limited Sequence for-loop path.
// scan/fold/reduce still resolve to runtime ABI stubs at call sites until
// source-backed iteration parity is complete (see MIGRATION-SEQ-004b notes).

public fun <T, R> Sequence<T>.fold(initial: R, operation: (R, T) -> R): R {
    val elements = this.toList()
    var accumulator = initial
    var i = 0
    while (i < elements.size) {
        accumulator = operation(accumulator, elements[i])
        i += 1
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
    val elements = this.toList()
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < elements.size) {
        accumulator = operation(accumulator, elements[i])
        result.add(accumulator)
        i += 1
    }
    // Public Sema still exposes Sequence<R>; sequence runtime consumers accept list handles.
    return result
}

// Sema exposes the public call result as Map<K, V>; the source body returns the
// mutable implementation type to avoid current MutableMap-to-Map coercion noise.
public fun <T, K, V> Sequence<T>.associate(transform: (T) -> Pair<K, V>): MutableMap<K, V> {
    val elements = this.toList()
    val result = mutableMapOf<K, V>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        val pair = transform(elem)
        result[pair.first] = pair.second
        i += 1
    }
    return result
}

public fun <T, K> Sequence<T>.associateBy(keySelector: (T) -> K): MutableMap<K, T> {
    val elements = this.toList()
    val result = mutableMapOf<K, T>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        result[keySelector(elem)] = elem
        i += 1
    }
    return result
}

public fun <T, K, V> Sequence<T>.associateBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): MutableMap<K, V> {
    val elements = this.toList()
    val result = mutableMapOf<K, V>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        result[keySelector(elem)] = valueTransform(elem)
        i += 1
    }
    return result
}

public fun <T, K> Sequence<T>.groupBy(keySelector: (T) -> K): MutableMap<K, MutableList<T>> {
    val elements = this.toList()
    val result = mutableMapOf<K, MutableList<T>>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
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
    return result
}

public fun <T, K, V> Sequence<T>.groupBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): MutableMap<K, MutableList<V>> {
    val elements = this.toList()
    val result = mutableMapOf<K, MutableList<V>>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
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
    return result
}

public fun <T> Sequence<T>.sumOf(selector: (T) -> Int): Int {
    val elements = this.toList()
    var sum = 0
    var i = 0
    while (i < elements.size) {
        sum += selector(elements[i])
        i += 1
    }
    return sum
}

public fun <T, R : Comparable<R>> Sequence<T>.maxByOrNull(selector: (T) -> R): T? {
    val elements = this.toList()
    var bestElem: T? = null
    var bestKey: R? = null
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        val key = selector(elem)
        val currentBestKey = bestKey
        if (currentBestKey == null || key.compareTo(currentBestKey) > 0) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T, R : Comparable<R>> Sequence<T>.minByOrNull(selector: (T) -> R): T? {
    val elements = this.toList()
    var bestElem: T? = null
    var bestKey: R? = null
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        val key = selector(elem)
        val currentBestKey = bestKey
        if (currentBestKey == null || key.compareTo(currentBestKey) < 0) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}
