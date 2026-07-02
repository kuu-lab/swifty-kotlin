package kotlin.sequences

// MIGRATION-SEQ-004
// Sequence aggregate HOFs migrated to Kotlin source.
//
// Migration source:
//   Sources/Runtime/RuntimeSequence.swift
//   Sources/Runtime/RuntimeSequenceAssociation.swift
//   Sources/Runtime/RuntimeSequenceFoldScan.swift
//
// Implementations prefer `for` loops where the current lowering path supports
// them; reduce uses toList() to avoid nullable generic accumulator handling.

public fun <T, R> Sequence<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    for (elem in this) {
        accumulator = operation(accumulator, elem)
    }
    return accumulator
}

public fun <T> Sequence<T>.reduce(operation: (T, T) -> T): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw UnsupportedOperationException("Empty sequence can't be reduced.")
    var accumulator = elements[0]
    var i = 1
    while (i < elements.size) {
        accumulator = operation(accumulator, elements[i])
        i += 1
    }
    return accumulator
}

public fun <T, R> Sequence<T>.scan(initial: R, operation: (R, T) -> R): Sequence<R> {
    return this.runningFold(initial, operation)
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
        if (bestKey == null || key.compareTo(bestKey!!) > 0) { bestElem = elem; bestKey = key }
    }
    return bestElem
}

public fun <T, R : Comparable<R>> Sequence<T>.minByOrNull(selector: (T) -> R): T? {
    var bestElem: T? = null
    var bestKey: R? = null
    for (elem in this) {
        val key = selector(elem)
        if (bestKey == null || key.compareTo(bestKey!!) < 0) { bestElem = elem; bestKey = key }
    }
    return bestElem
}
