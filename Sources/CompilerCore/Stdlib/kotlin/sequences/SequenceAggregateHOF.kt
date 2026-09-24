package kotlin.collections

import kotlin.comparisons.minOf as comparisonMinOf
import kotlin.internal.__valuesEqual

// Float/Double maxOf uses these existing shared numeric helpers directly, the
// same way Iterables.kt does, so NaN and signed-zero behavior stays identical
// to kotlin.comparisons.maxOf (calling that inline wrapper itself by
// fully-qualified name from a non-inline caller left an unresolved "_maxOf"
// symbol at link time in --stdlib-from-source mode). minOf uses the
// comparisonMinOf import alias above instead of a local kk_min_float/double
// redeclaration — a local redeclaration of kk_min_float produced wrong
// results (returned the first operand unchanged) when called directly.
private external fun kk_max_float(a: Float, b: Float): Float
private external fun kk_max_double(a: Double, b: Double): Double

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
// Migrated: reduceRight, reduceRightOrNull, reduceRightIndexed, reduceRightIndexedOrNull,
//           scan, scanIndexed, runningFold, runningFoldIndexed, runningReduce,
//           runningReduceIndexed, sumOf, maxByOrNull, minByOrNull, associate, associateBy,
//           groupBy, Sequence.toMap
//
// reduce/reduceOrNull/reduceIndexed/reduceIndexedOrNull moved to
// SequenceConversionsAndSetOps.kt (package kotlin.sequences) with the canonical
// <S, T : S> signature in KSP-1355.
//
// Sorting variants are in SequenceSortingHOF.kt (package kotlin.sequences) to avoid
// FQ-name collisions with List sorting extensions.
//
// Implementations materialize through toList() before looping so they reuse the
// stable list indexing path instead of the still-limited Sequence for-loop path.

public fun <T> Sequence<T>.reduceRight(operation: (T, T) -> T): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw UnsupportedOperationException("Empty sequence can't be reduced.")
    var accumulator = elements[elements.size - 1]
    var i = elements.size - 2
    while (i >= 0) {
        accumulator = operation(elements[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Sequence<T>.reduceRightOrNull(operation: (T, T) -> T): T? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var accumulator = elements[elements.size - 1]
    var i = elements.size - 2
    while (i >= 0) {
        accumulator = operation(elements[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Sequence<T>.reduceRightIndexed(operation: (Int, T, T) -> T): T {
    val elements = this.toList()
    if (elements.isEmpty()) throw UnsupportedOperationException("Empty sequence can't be reduced.")
    var accumulator = elements[elements.size - 1]
    var i = elements.size - 2
    while (i >= 0) {
        accumulator = operation(i, elements[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Sequence<T>.reduceRightIndexedOrNull(operation: (Int, T, T) -> T): T? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var accumulator = elements[elements.size - 1]
    var i = elements.size - 2
    while (i >= 0) {
        accumulator = operation(i, elements[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T, R> Sequence<T>.scan(initial: R, operation: (R, T) -> R): Sequence<R> {
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
    return result.asSequence()
}

public fun <T, R> Sequence<T>.scanIndexed(initial: R, operation: (Int, R, T) -> R): Sequence<R> {
    val elements = this.toList()
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < elements.size) {
        accumulator = operation(i, accumulator, elements[i])
        result.add(accumulator)
        i += 1
    }
    return result.asSequence()
}

public fun <T, R> Sequence<T>.runningFold(initial: R, operation: (R, T) -> R): Sequence<R> =
    scan(initial, operation)

public fun <T, R> Sequence<T>.runningFoldIndexed(initial: R, operation: (Int, R, T) -> R): Sequence<R> =
    scanIndexed(initial, operation)

public fun <T> Sequence<T>.runningReduce(operation: (T, T) -> T): Sequence<T> {
    val elements = this.toList()
    val result = mutableListOf<T>()
    if (elements.isEmpty()) return result.asSequence()
    var accumulator = elements[0]
    result.add(accumulator)
    var i = 1
    while (i < elements.size) {
        accumulator = operation(accumulator, elements[i])
        result.add(accumulator)
        i += 1
    }
    return result.asSequence()
}

public fun <T> Sequence<T>.runningReduceIndexed(operation: (Int, T, T) -> T): Sequence<T> {
    val elements = this.toList()
    val result = mutableListOf<T>()
    if (elements.isEmpty()) return result.asSequence()
    var accumulator = elements[0]
    result.add(accumulator)
    var i = 1
    while (i < elements.size) {
        accumulator = operation(i, accumulator, elements[i])
        result.add(accumulator)
        i += 1
    }
    return result.asSequence()
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> Sequence<Pair<K, V>>.toMap(): Map<K, V> {
    val result = mutableMapOf<K, V>()
    val pairs = this.toList()
    for (pair in pairs) result[pair.first] = pair.second
    return result as Map<K, V>
}

@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public fun <K, V, M : MutableMap<in K, in V>> Sequence<Pair<K, V>>.toMap(destination: M): M {
    val mutableDestination = destination as MutableMap<K, V>
    for (pair in this) mutableDestination[pair.first] = pair.second
    return destination
}

// KSP-1340: Sequence associate-family decls carry the Kotlin 2.3.10 signatures —
// Map<…> results and generic `M : MutableMap<in …>` destinations — matching the
// Iterable counterparts in Iterables.kt.
@Suppress("UNCHECKED_CAST")
public inline fun <T, K, V> Sequence<T>.associate(transform: (T) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K> Sequence<T>.associateBy(keySelector: (T) -> K): Map<K, T> {
    val result = mutableMapOf<K, T>()
    for (element in this) result[keySelector(element)] = element
    return result as Map<K, T>
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K, V> Sequence<T>.associateBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result as Map<K, V>
}

// KSP-1348: Sequence group-family decls carry the Kotlin 2.3.10 signatures —
// Map<K, List<…>> results and generic `M : MutableMap<in K, …>` destinations —
// matching the Iterable counterparts in Iterables.kt.
@Suppress("UNCHECKED_CAST")
public inline fun <T, K> Sequence<T>.groupBy(keySelector: (T) -> K): Map<K, List<T>> {
    val result = mutableMapOf<K, MutableList<T>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<T>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, K, V> Sequence<T>.groupBy(
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
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

// KSP-1353/KSP-1354: the generic Comparable overloads below now share their
// name with the Double/Float-specialized overloads added further down, so
// all of them opt into @OverloadResolutionByLambdaReturnType (matching
// kotlin.collections.Iterable's maxOf/minOf family in Iterables.kt) —
// otherwise the lambda's inferred return type can't disambiguate which
// overload a call site means.
@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R : Comparable<R>> Sequence<T>.minOf(selector: (T) -> R): R {
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

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R : Comparable<R>> Sequence<T>.maxOf(selector: (T) -> R): R {
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

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R : Comparable<R>> Sequence<T>.minOfOrNull(selector: (T) -> R): R? {
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

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T, R : Comparable<R>> Sequence<T>.maxOfOrNull(selector: (T) -> R): R? {
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

// KSP-1353/KSP-1354: Double/Float-specialized maxOf/minOf overloads and the
// Comparator-based maxOfWith/minOfWith. maxOf delegates pairwise comparisons
// to kk_max_double/kk_max_float directly, the same way Iterables.kt's own
// maxOf(Double|Float) does; minOf goes through the comparisonMinOf import
// alias at the top of this file instead (see that alias's own comment for
// why). Either way this keeps NaN propagation and signed-zero ordering
// matching Kotlin's IEEE-754 pairwise semantics, instead of the
// Comparable.compareTo total ordering used by the generic
// <T : Comparable<T>> overloads above.

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.maxOf(selector: (T) -> Double): Double {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = kk_max_double(result, selector(elements[i]))
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.maxOf(selector: (T) -> Float): Float {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = kk_max_float(result, selector(elements[i]))
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.maxOfOrNull(selector: (T) -> Double): Double? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = kk_max_double(result, selector(elements[i]))
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.maxOfOrNull(selector: (T) -> Float): Float? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = kk_max_float(result, selector(elements[i]))
        i += 1
    }
    return result
}

public fun <T, R> Sequence<T>.maxOfWith(comparator: Comparator<in R>, selector: (T) -> R): R {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val value = selector(elements[i])
        if (comparator.compare(result, value) < 0) result = value
        i += 1
    }
    return result
}

public fun <T, R> Sequence<T>.maxOfWithOrNull(comparator: Comparator<in R>, selector: (T) -> R): R? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val value = selector(elements[i])
        if (comparator.compare(result, value) < 0) result = value
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.minOf(selector: (T) -> Double): Double {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = comparisonMinOf(result, selector(elements[i]))
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.minOf(selector: (T) -> Float): Float {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = comparisonMinOf(result, selector(elements[i]))
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.minOfOrNull(selector: (T) -> Double): Double? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = comparisonMinOf(result, selector(elements[i]))
        i += 1
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <T> Sequence<T>.minOfOrNull(selector: (T) -> Float): Float? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        result = comparisonMinOf(result, selector(elements[i]))
        i += 1
    }
    return result
}

public fun <T, R> Sequence<T>.minOfWith(comparator: Comparator<in R>, selector: (T) -> R): R {
    val elements = this.toList()
    if (elements.isEmpty()) throw NoSuchElementException("Sequence is empty.")
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val value = selector(elements[i])
        if (comparator.compare(result, value) > 0) result = value
        i += 1
    }
    return result
}

public fun <T, R> Sequence<T>.minOfWithOrNull(comparator: Comparator<in R>, selector: (T) -> R): R? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var result = selector(elements[0])
    var i = 1
    while (i < elements.size) {
        val value = selector(elements[i])
        if (comparator.compare(result, value) > 0) result = value
        i += 1
    }
    return result
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

@IgnorableReturnValue
public inline fun <T, K, V, M : MutableMap<in K, in V>> Sequence<T>.associateTo(
    destination: M,
    transform: (T) -> Pair<K, V>
): M {
    for (element in this) {
        val pair = transform(element)
        destination.put(pair.first, pair.second)
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, K, M : MutableMap<in K, in T>> Sequence<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K
): M {
    for (element in this) destination.put(keySelector(element), element)
    return destination
}

@IgnorableReturnValue
public inline fun <T, K, V, M : MutableMap<in K, in V>> Sequence<T>.associateByTo(
    destination: M,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): M {
    for (element in this) destination.put(keySelector(element), valueTransform(element))
    return destination
}

@SinceKotlin("1.3")
@Suppress("UNCHECKED_CAST")
public inline fun <T, V> Sequence<T>.associateWith(valueTransform: (T) -> V): Map<T, V> {
    val result = mutableMapOf<T, V>()
    for (element in this) result[element] = valueTransform(element)
    return result as Map<T, V>
}

@SinceKotlin("1.3")
@IgnorableReturnValue
public inline fun <T, V, M : MutableMap<in T, in V>> Sequence<T>.associateWithTo(
    destination: M,
    valueTransform: (T) -> V
): M {
    for (element in this) destination.put(element, valueTransform(element))
    return destination
}

@IgnorableReturnValue
public inline fun <T, K, M : MutableMap<in K, MutableList<T>>> Sequence<T>.groupByTo(
    destination: M,
    keySelector: (T) -> K
): M {
    for (element in this) {
        val key = keySelector(element)
        val existing = destination[key]
        if (existing == null) {
            val bucket = mutableListOf<T>()
            bucket.add(element)
            destination[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, K, V, M : MutableMap<in K, MutableList<V>>> Sequence<T>.groupByTo(
    destination: M,
    keySelector: (T) -> K,
    valueTransform: (T) -> V
): M {
    for (element in this) {
        val key = keySelector(element)
        val existing = destination[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            destination[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
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

// KSP-1350: Sequence join-family decls carry the Kotlin 2.3.10 signatures —
// generic `A : Appendable` buffers and `CharSequence` separator/prefix/postfix/
// truncated — matching the Iterable counterparts in Iterables.kt, whose shared
// appendJoinToAppendable* helpers they call through iterator() (KSP-621).
@IgnorableReturnValue
public fun <T, A : Appendable> Sequence<T>.joinTo(
    buffer: A,
    separator: CharSequence = ", ",
    prefix: CharSequence = "",
    postfix: CharSequence = "",
    limit: Int = -1,
    truncated: CharSequence = "..."
): A = appendJoinToAppendablePlain(this.iterator(), buffer, separator, prefix, postfix, limit, truncated)

@IgnorableReturnValue
public fun <T, A : Appendable> Sequence<T>.joinTo(
    buffer: A,
    separator: CharSequence = ", ",
    prefix: CharSequence = "",
    postfix: CharSequence = "",
    limit: Int = -1,
    truncated: CharSequence = "...",
    transform: (T) -> CharSequence
): A = appendJoinToAppendableTransform(this.iterator(), buffer, separator, prefix, postfix, limit, truncated, transform)

public fun <T> Sequence<T>.joinToString(
    separator: CharSequence = ", ",
    prefix: CharSequence = "",
    postfix: CharSequence = "",
    limit: Int = -1,
    truncated: CharSequence = "..."
): String = appendJoinToAppendablePlain(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated).toString()

public fun <T> Sequence<T>.joinToString(
    separator: CharSequence = ", ",
    prefix: CharSequence = "",
    postfix: CharSequence = "",
    limit: Int = -1,
    truncated: CharSequence = "...",
    transform: (T) -> CharSequence
): String = appendJoinToAppendableTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated, transform).toString()
// KSP-442: Sequence terminal operations migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSequence.swift

public fun <T> Sequence<T>.first(): T {
    val elements = this.toList()
    if (elements.size == 0) throw NoSuchElementException("Sequence is empty.")
    return elements[0]
}

public fun <T> Sequence<T>.first(predicate: (T) -> Boolean): T {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        val element = elements[i]
        if (predicate(element)) return element
        i += 1
    }
    throw NoSuchElementException("Sequence contains no element matching the predicate.")
}

public fun <T> Sequence<T>.firstOrNull(): T? {
    val elements = this.toList()
    if (elements.size == 0) return null
    return elements[0]
}

public fun <T> Sequence<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        val element = elements[i]
        if (predicate(element)) return element
        i += 1
    }
    return null
}

public fun <T> Sequence<T>.last(): T {
    val elements = this.toList()
    if (elements.size == 0) throw NoSuchElementException("Sequence is empty.")
    return elements[elements.size - 1]
}

public fun <T> Sequence<T>.last(predicate: (T) -> Boolean): T {
    val elements = this.toList()
    var i = elements.size - 1
    while (i >= 0) {
        val element = elements[i]
        if (predicate(element)) return element
        i -= 1
    }
    throw NoSuchElementException("Sequence contains no element matching the predicate.")
}

public fun <T> Sequence<T>.lastOrNull(): T? {
    val elements = this.toList()
    if (elements.size == 0) return null
    return elements[elements.size - 1]
}

public fun <T> Sequence<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    val elements = this.toList()
    var i = elements.size - 1
    while (i >= 0) {
        val element = elements[i]
        if (predicate(element)) return element
        i -= 1
    }
    return null
}

public fun <T> Sequence<T>.elementAt(index: Int): T {
    val elements = this.toList()
    if (index < 0 || index >= elements.size) {
        throw IndexOutOfBoundsException("Index $index out of bounds for length ${elements.size}")
    }
    return elements[index]
}

public fun <T> Sequence<T>.elementAtOrNull(index: Int): T? {
    val elements = this.toList()
    if (index >= 0 && index < elements.size) {
        return elements[index]
    }
    return null
}

public fun <T> Sequence<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T {
    val elements = this.toList()
    if (index >= 0 && index < elements.size) {
        return elements[index]
    }
    return defaultValue(index)
}

public fun <T> Sequence<T>.indexOf(element: T): Int {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        if (__valuesEqual(elements[i], element)) return i
        i += 1
    }
    return -1
}

public fun <T> Sequence<T>.indexOfFirst(predicate: (T) -> Boolean): Int {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        if (predicate(elements[i])) return i
        i += 1
    }
    return -1
}

public fun <T> Sequence<T>.indexOfLast(predicate: (T) -> Boolean): Int {
    val elements = this.toList()
    var i = elements.size - 1
    while (i >= 0) {
        if (predicate(elements[i])) return i
        i -= 1
    }
    return -1
}

public fun <T> Sequence<T>.lastIndexOf(element: T): Int {
    val elements = this.toList()
    var i = elements.size - 1
    while (i >= 0) {
        if (__valuesEqual(elements[i], element)) return i
        i -= 1
    }
    return -1
}

public operator fun <T> Sequence<T>.contains(element: T): Boolean = indexOf(element) >= 0

public fun <T> Sequence<T>.any(): Boolean {
    val elements = this.toList()
    return elements.size > 0
}

public fun <T> Sequence<T>.any(predicate: (T) -> Boolean): Boolean {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        if (predicate(elements[i])) return true
        i += 1
    }
    return false
}

public fun <T> Sequence<T>.all(predicate: (T) -> Boolean): Boolean {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        if (!predicate(elements[i])) return false
        i += 1
    }
    return true
}

public fun <T> Sequence<T>.none(): Boolean {
    val elements = this.toList()
    return elements.size == 0
}

public fun <T> Sequence<T>.none(predicate: (T) -> Boolean): Boolean {
    val elements = this.toList()
    var i = 0
    val sz = elements.size
    while (i < sz) {
        if (predicate(elements[i])) return false
        i += 1
    }
    return true
}

public fun <T> Sequence<T>.count(): Int {
    val elements = this.toList()
    return elements.size
}

public fun <T> Sequence<T>.count(predicate: (T) -> Boolean): Int {
    val elements = this.toList()
    var count = 0
    var i = 0
    val sz = elements.size
    while (i < sz) {
        if (predicate(elements[i])) count += 1
        i += 1
    }
    return count
}

// KSP-1353: Double/Float-specialized maxOrNull()/max() overloads, mirroring
// Iterables.kt's own specializations. Pairwise kk_max_double/kk_max_float
// keeps NaN propagation and signed-zero ordering on Kotlin's IEEE-754
// semantics instead of the Comparable.compareTo total ordering used by the
// generic <T : Comparable<T>> overloads below. These declarations sit ahead
// of the generic ones so the Sequence aggregate fast path's first-match
// lookup prefers them for concrete Double/Float receivers; other element
// types still resolve to the generic overloads through the receiver
// element-type filter.
@SinceKotlin("1.4")
public fun Sequence<Double>.maxOrNull(): Double? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var max = elements[0]
    var i = 1
    val sz = elements.size
    while (i < sz) {
        max = kk_max_double(max, elements[i])
        i += 1
    }
    return max
}

@SinceKotlin("1.4")
public fun Sequence<Float>.maxOrNull(): Float? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var max = elements[0]
    var i = 1
    val sz = elements.size
    while (i < sz) {
        max = kk_max_float(max, elements[i])
        i += 1
    }
    return max
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun Sequence<Double>.max(): Double = maxOrNull() ?: throw NoSuchElementException("Sequence is empty.")

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun Sequence<Float>.max(): Float = maxOrNull() ?: throw NoSuchElementException("Sequence is empty.")

public fun <T : Comparable<T>> Sequence<T>.maxOrNull(): T? {
    val elements = this.toList()
    var best: T? = null
    var i = 0
    val sz = elements.size
    while (i < sz) {
        val element = elements[i]
        val current = best
        if (current == null || element.compareTo(current) > 0) best = element
        i += 1
    }
    return best
}

public fun <T : Comparable<T>> Sequence<T>.max(): T = maxOrNull() ?: throw NoSuchElementException("Sequence is empty.")

// KSP-1354: Double/Float-specialized minOrNull()/min() overloads, mirroring
// Iterables.kt's own specializations. Pairwise comparisonMinOf keeps NaN
// propagation and signed-zero ordering on Kotlin's IEEE-754 semantics instead
// of the Comparable.compareTo total ordering used by the generic
// <T : Comparable<T>> overloads below. These declarations sit ahead of the
// generic ones so the Sequence aggregate fast path's first-match lookup
// prefers them for concrete Double/Float receivers; other element types still
// resolve to the generic overloads through the receiver element-type filter.
@SinceKotlin("1.4")
public fun Sequence<Double>.minOrNull(): Double? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var min = elements[0]
    var i = 1
    val sz = elements.size
    while (i < sz) {
        min = comparisonMinOf(min, elements[i])
        i += 1
    }
    return min
}

@SinceKotlin("1.4")
public fun Sequence<Float>.minOrNull(): Float? {
    val elements = this.toList()
    if (elements.isEmpty()) return null
    var min = elements[0]
    var i = 1
    val sz = elements.size
    while (i < sz) {
        min = comparisonMinOf(min, elements[i])
        i += 1
    }
    return min
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("minOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun Sequence<Double>.min(): Double = minOrNull() ?: throw NoSuchElementException("Sequence is empty.")

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("minOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
public fun Sequence<Float>.min(): Float = minOrNull() ?: throw NoSuchElementException("Sequence is empty.")

public fun <T : Comparable<T>> Sequence<T>.minOrNull(): T? {
    val elements = this.toList()
    var best: T? = null
    var i = 0
    val sz = elements.size
    while (i < sz) {
        val element = elements[i]
        val current = best
        if (current == null || element.compareTo(current) < 0) best = element
        i += 1
    }
    return best
}

public fun <T : Comparable<T>> Sequence<T>.min(): T = minOrNull() ?: throw NoSuchElementException("Sequence is empty.")

public fun Sequence<Int>.sum(): Int {
    val elements = this.toList()
    var sum = 0
    var i = 0
    val sz = elements.size
    while (i < sz) {
        sum += elements[i]
        i += 1
    }
    return sum
}

public fun Sequence<Int>.average(): Double {
    val elements = this.toList()
    val sz = elements.size
    if (sz == 0) return 0.0 / 0.0
    var sum = 0
    var i = 0
    while (i < sz) {
        sum += elements[i]
        i += 1
    }
    return sum.toDouble() / sz
}
