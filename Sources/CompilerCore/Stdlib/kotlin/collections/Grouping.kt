/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/Grouping.kt>.
 */

package kotlin.collections

/**
 * Represents a source of elements with a [keyOf] function, which can be applied to each element
 * to get its key.
 */
public interface Grouping<T, out K> {
    /** Returns an [Iterator] over the elements of the source of this grouping. */
    public fun sourceIterator(): Iterator<T>

    /** Extracts the key of an [element]. */
    public fun keyOf(element: T): K
}

/**
 * Creates a [Grouping] source from an iterable to be used later with one of group-and-fold operations
 * using the specified [keySelector] function to extract a key from each element.
 */
public fun <T, K> Iterable<T>.groupingBy(keySelector: (T) -> K): Grouping<T, K> {
    val source = this
    return object : Grouping<T, K> {
        override fun sourceIterator(): Iterator<T> = source.iterator()
        override fun keyOf(element: T): K = keySelector(element)
    }
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, passing the previously accumulated value and the current element as arguments, and stores
 * the results in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.aggregateTo(
    destination: MutableMap<K, R>,
    operation: (K, R?, T, Boolean) -> R
): MutableMap<K, R> {
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val accumulator = destination[key]
        val first = accumulator == null && !destination.containsKey(key)
        destination[key] = operation(key, accumulator, element, first)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, passing the previously accumulated value and the current element as arguments.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.aggregate(
    operation: (K, R?, T, Boolean) -> R
): Map<K, R> = aggregateTo(mutableMapOf<K, R>(), operation) as Map<K, R>

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with the value provided by [initialValueSelector], and stores the results
 * in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.foldTo(
    destination: MutableMap<K, R>,
    initialValueSelector: (K, T) -> R,
    operation: (K, R, T) -> R
): MutableMap<K, R> {
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = destination[key]
        val accumulator = if (current == null && !destination.containsKey(key)) {
            initialValueSelector(key, element)
        } else {
            current as R
        }
        destination[key] = operation(key, accumulator, element)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with the value provided by [initialValueSelector].
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.fold(
    initialValueSelector: (K, T) -> R,
    operation: (K, R, T) -> R
): Map<K, R> = foldTo(mutableMapOf<K, R>(), initialValueSelector, operation) as Map<K, R>

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with [initialValue], and stores the results in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.foldTo(
    destination: MutableMap<K, R>,
    initialValue: R,
    operation: (R, T) -> R
): MutableMap<K, R> {
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = destination[key]
        val accumulator = if (current == null && !destination.containsKey(key)) {
            initialValue
        } else {
            current as R
        }
        destination[key] = operation(accumulator, element)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with [initialValue].
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.fold(
    initialValue: R,
    operation: (R, T) -> R
): Map<K, R> = foldTo(mutableMapOf<K, R>(), initialValue, operation) as Map<K, R>

/**
 * Groups elements from the [Grouping] source by key and applies the reducing [operation] to the elements
 * of each group sequentially, storing the results in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K> Grouping<T, K>.reduceTo(
    destination: MutableMap<K, T>,
    operation: (K, T, T) -> T
): MutableMap<K, T> {
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = destination[key]
        val accumulator = if (current == null && !destination.containsKey(key)) {
            element
        } else {
            operation(key, current as T, element)
        }
        destination[key] = accumulator
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies the reducing [operation] to the elements
 * of each group sequentially.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K> Grouping<T, K>.reduce(
    operation: (K, T, T) -> T
): Map<K, T> = reduceTo(mutableMapOf<K, T>(), operation) as Map<K, T>

/**
 * Groups elements from the [Grouping] source by key and counts elements in each group
 * into the given [destination] map.
 */
public fun <T, K> Grouping<T, K>.eachCountTo(destination: MutableMap<K, Int>): MutableMap<K, Int> {
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = destination[key]
        destination[key] = if (current == null) 1 else current + 1
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and counts elements in each group.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K> Grouping<T, K>.eachCount(): Map<K, Int> =
    eachCountTo(mutableMapOf<K, Int>()) as Map<K, Int>
