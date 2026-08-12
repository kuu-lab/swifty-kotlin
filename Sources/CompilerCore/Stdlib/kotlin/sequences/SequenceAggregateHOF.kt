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

public fun <T, R : Comparable<R>> Sequence<T>.minBy(selector: (T) -> R): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var bestElem = elements[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < elements.size) {
        val elem = elements[i]
        val key = selector(elem)
        if (key.compareTo(bestKey) < 0) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T, R : Comparable<R>> Sequence<T>.maxBy(selector: (T) -> R): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var bestElem = elements[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < elements.size) {
        val elem = elements[i]
        val key = selector(elem)
        if (key.compareTo(bestKey) > 0) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T, R : Comparable<R>> Sequence<T>.minOf(selector: (T) -> R): R {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var bestKey = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val key = selector(elements[i])
        if (key.compareTo(bestKey) < 0) bestKey = key
        i += 1
    }
    return bestKey
}

public fun <T, R : Comparable<R>> Sequence<T>.maxOf(selector: (T) -> R): R {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var bestKey = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val key = selector(elements[i])
        if (key.compareTo(bestKey) > 0) bestKey = key
        i += 1
    }
    return bestKey
}

public fun <T, R : Comparable<R>> Sequence<T>.minOfOrNull(selector: (T) -> R): R? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var bestKey = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val key = selector(elements[i])
        if (key.compareTo(bestKey) < 0) bestKey = key
        i += 1
    }
    return bestKey
}

public fun <T, R : Comparable<R>> Sequence<T>.maxOfOrNull(selector: (T) -> R): R? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var bestKey = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val key = selector(elements[i])
        if (key.compareTo(bestKey) > 0) bestKey = key
        i += 1
    }
    return bestKey
}

public fun <T> Sequence<T>.minWith(comparator: Comparator<in T>): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var best = elements[0]
    var i = 1
    while (i < elements.size) {
        val elem = elements[i]
        if (comparator.compare(elem, best) < 0) best = elem
        i += 1
    }
    return best
}

public fun <T> Sequence<T>.maxWith(comparator: Comparator<in T>): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var best = elements[0]
    var i = 1
    while (i < elements.size) {
        val elem = elements[i]
        if (comparator.compare(elem, best) > 0) best = elem
        i += 1
    }
    return best
}

public fun <T> Sequence<T>.minWithOrNull(comparator: Comparator<in T>): T? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var best = elements[0]
    var i = 1
    while (i < elements.size) {
        val elem = elements[i]
        if (comparator.compare(elem, best) < 0) best = elem
        i += 1
    }
    return best
}

public fun <T> Sequence<T>.maxWithOrNull(comparator: Comparator<in T>): T? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var best = elements[0]
    var i = 1
    while (i < elements.size) {
        val elem = elements[i]
        if (comparator.compare(elem, best) > 0) best = elem
        i += 1
    }
    return best
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public fun <T> Sequence<T>.sumBy(selector: (T) -> Int): Int = sumOf(selector)

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public fun <T> Sequence<T>.sumByDouble(selector: (T) -> Double): Double = sumOf(selector)

public fun <T> Sequence<T>.sumOf(selector: (T) -> Double): Double {
    val elements = this.toList()
    var sum = 0.0
    var i = 0
    while (i < elements.size) {
        sum += selector(elements[i])
        i += 1
    }
    return sum
}

public fun <T, K, V> Sequence<T>.associateTo(destination: MutableMap<K, V>, transform: (T) -> Pair<K, V>): MutableMap<K, V> {
    val elements = this.toList()
    var i = 0
    while (i < elements.size) {
        val pair = transform(elements[i])
        destination[pair.first] = pair.second
        i += 1
    }
    return destination
}

public fun <T, K> Sequence<T>.associateByTo(destination: MutableMap<K, T>, keySelector: (T) -> K): MutableMap<K, T> {
    val elements = this.toList()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        destination[keySelector(elem)] = elem
        i += 1
    }
    return destination
}

public fun <T, K, V> Sequence<T>.associateByTo(
    destination: MutableMap<K, V>,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): MutableMap<K, V> {
    val elements = this.toList()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        destination[keySelector(elem)] = valueTransform(elem)
        i += 1
    }
    return destination
}

public fun <T, V> Sequence<T>.associateWith(valueTransform: (T) -> V): MutableMap<T, V> {
    val elements = this.toList()
    val result = mutableMapOf<T, V>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        result[elem] = valueTransform(elem)
        i += 1
    }
    return result
}

public fun <T, V> Sequence<T>.associateWithTo(destination: MutableMap<T, V>, valueTransform: (T) -> V): MutableMap<T, V> {
    val elements = this.toList()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        destination[elem] = valueTransform(elem)
        i += 1
    }
    return destination
}

public fun <T, K> Sequence<T>.groupByTo(destination: MutableMap<K, MutableList<T>>, keySelector: (T) -> K): MutableMap<K, MutableList<T>> {
    val elements = this.toList()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        val key = keySelector(elem)
        val existing = destination[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(elem)
            destination[key] = bucket
        } else {
            existing.add(elem)
        }
        i += 1
    }
    return destination
}

public fun <T, K, V> Sequence<T>.groupByTo(
    destination: MutableMap<K, MutableList<V>>,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): MutableMap<K, MutableList<V>> {
    val elements = this.toList()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        val key = keySelector(elem)
        val value = valueTransform(elem)
        val existing = destination[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(value)
            destination[key] = bucket
        } else {
            existing.add(value)
        }
        i += 1
    }
    return destination
}

public fun <T> Sequence<T>.partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> {
    val elements = this.toList()
    val matched = mutableListOf<T>()
    val unmatched = mutableListOf<T>()
    var i = 0
    while (i < elements.size) {
        val elem = elements[i]
        if (predicate(elem)) matched.add(elem) else unmatched.add(elem)
        i += 1
    }
    return Pair(matched.toList(), unmatched.toList())
}

public fun <T> Sequence<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder {
    buffer.append(prefix)
    val elements = this.toList()
    var first = true
    var i = 0
    while (i < elements.size) {
        if (!first) buffer.append(separator)
        buffer.append(elements[i].toString())
        first = false
        i += 1
    }
    buffer.append(postfix)
    return buffer
}

public fun <T> Sequence<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (T) -> Any
): StringBuilder {
    buffer.append(prefix)
    val elements = this.toList()
    var first = true
    var i = 0
    while (i < elements.size) {
        if (!first) buffer.append(separator)
        buffer.append(transform(elements[i]).toString())
        first = false
        i += 1
    }
    buffer.append(postfix)
    return buffer
}

public fun <T> Sequence<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = joinTo(StringBuilder(), separator, prefix, postfix).toString()

public fun <T> Sequence<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String {
    val buffer = StringBuilder()
    buffer.append(prefix)
    val elements = this.toList()
    var first = true
    var i = 0
    while (i < elements.size) {
        if (!first) buffer.append(separator)
        buffer.append(transform(elements[i]).toString())
        first = false
        i += 1
    }
    buffer.append(postfix)
    return buffer.toString()
}

public fun <T> Sequence<T>.joinToString(
    separator: String,
    prefix: String,
    transform: (T) -> Any
): String = joinToString(separator, prefix, "", transform)

public fun <T> Sequence<T>.joinToString(
    separator: String,
    transform: (T) -> Any
): String = joinToString(separator, "", "", transform)

public fun <T> Sequence<T>.joinToString(
    transform: (T) -> Any
): String = joinToString(", ", "", "", transform)
