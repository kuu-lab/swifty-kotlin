package kotlin.collections

import kotlin.comparisons.naturalOrder
import kotlin.comparisons.reverseOrder
import kotlin.internal.mergeSortWith

// Set HOF implementations migrated from Swift Runtime
// MIGRATION-COL-013

fun <T> Set<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

inline fun <T, R> Set<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        result.add(transform(element))
    }
    return result
}

fun <T, R> Set<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        for (subElement in transform(element)) {
            result.add(subElement)
        }
    }
    return result
}

inline fun <T> Set<T>.forEach(action: (T) -> Unit) {
    for (element in this) {
        action(element)
    }
}

fun <T> Set<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    for (element in this) {
        if (predicate(element)) count++
    }
    return count
}

public fun <T> Set<T>.none(): Boolean = size == 0

fun <T> Set<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

fun <T> Set<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

fun <T> Set<T>.none(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return false
    }
    return true
}

public inline fun <T, R> Set<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    for (element in this) {
        accumulator = operation(accumulator, element)
    }
    return accumulator
}

public inline fun <T, R> Set<T>.foldIndexed(initial: R, operation: (Int, R, T) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index += 1
    }
    return accumulator
}

// KSP-432: the remaining Set surface migrated from
//   Sources/Runtime/RuntimeCollectionHOF.swift
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//   Sources/Runtime/RuntimeCollections.swift
//   Sources/Runtime/RuntimeSetAndMap.swift
// Only element-storage primitives (`__kk_set_size`, `__kk_set_contains`,
// `__kk_set_is_empty`, `__kk_set_to_string`, `__kk_set_of`, `__kk_set_of_not_null`)
// stay in the runtime.
// Generic Iterable/Collection source from KSP-435 supplies `any()`, `last()`,
// `toList()`, `toMutableList()`, and `toMutableSet()` for Set receivers too.

public fun <T> Set<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) result.add(element)
    }
    return result
}

public fun <T, R : Any> Set<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val transformed = transform(element)
        if (transformed != null) result.add(transformed)
    }
    return result
}

public fun <T> Set<T>.first(): T {
    for (element in this) {
        return element
    }
    throw NoSuchElementException("Collection is empty.")
}

public fun <T> Set<T>.firstOrNull(): T? {
    for (element in this) {
        return element
    }
    return null
}

public fun <T> Set<T>.lastOrNull(): T? {
    var result: T? = null
    for (element in this) {
        result = element
    }
    return result
}

public fun <T> Set<T>.singleOrNull(): T? {
    var result: T? = null
    var count = 0
    for (element in this) {
        result = element
        count += 1
        if (count > 1) return null
    }
    if (count == 1) return result
    return null
}

public fun <T> Set<T>.containsAll(elements: Collection<out T>): Boolean {
    for (element in elements) {
        if (!this.contains(element)) return false
    }
    return true
}

public operator fun <T> Set<T>.minus(element: T): Set<T> {
    val result = mutableSetOf<T>()
    var removed = false
    for (item in this) {
        if (!removed && item == element) {
            removed = true
        } else {
            result.add(item)
        }
    }
    return result
}

public operator fun <T> Set<T>.minus(elements: Iterable<T>): Set<T> {
    if (isEmpty()) return toSet()

    val excluded = mutableSetOf<T>()
    for (element in elements) {
        excluded.add(element)
    }
    val result = mutableSetOf<T>()
    for (item in this) {
        if (!excluded.contains(item)) result.add(item)
    }
    return result
}

public operator fun <T> Set<T>.minus(elements: Sequence<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) {
        result.add(item)
    }
    for (element in elements) {
        result.remove(element)
    }
    return result
}

public operator fun <T> Set<T>.minus(elements: Array<out T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) {
        result.add(item)
    }
    for (element in elements) {
        result.remove(element)
    }
    return result
}

public inline fun <T> Set<T>.minusElement(element: T): Set<T> = minus(element)

public inline fun <T> Set<T>?.orEmpty(): Set<T> = this ?: emptySet()

public operator fun <T> Set<T>.plus(element: T): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) {
        result.add(item)
    }
    result.add(element)
    return result
}

public operator fun <T> Set<T>.plus(elements: Iterable<T>): Set<T> {
    if (elements is Collection<*> && elements.isEmpty()) return toSet()

    val result = mutableSetOf<T>()
    for (item in this) {
        result.add(item)
    }
    for (element in elements) {
        result.add(element)
    }
    return result
}

public operator fun <T> Set<T>.plus(elements: Sequence<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) {
        result.add(item)
    }
    for (element in elements) {
        result.add(element)
    }
    return result
}

public operator fun <T> Set<T>.plus(elements: Array<out T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) {
        result.add(item)
    }
    for (element in elements) {
        result.add(element)
    }
    return result
}

public inline fun <T> Set<T>.plusElement(element: T): Set<T> = plus(element)

public infix fun <T> Set<T>.intersect(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        if (other.contains(element)) result.add(element)
    }
    return result
}

public infix fun <T> Set<T>.union(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        result.add(element)
    }
    for (element in other) {
        result.add(element)
    }
    return result
}

public infix fun <T> Set<T>.subtract(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        if (!other.contains(element)) result.add(element)
    }
    return result
}

public fun <T : Comparable<T>> Set<T>.sorted(): List<T> {
    val result = this.toMutableList()
    result.mergeSortWith(naturalOrder())
    return result
}

public fun <T : Comparable<T>> Set<T>.sortedDescending(): List<T> {
    val result = this.toMutableList()
    result.mergeSortWith(reverseOrder())
    return result
}

public fun <T : Comparable<T>> Set<T>.maxOrNull(): T? {
    var best: T? = null
    for (element in this) {
        val current = best
        if (current == null || current.compareTo(element) < 0) best = element
    }
    return best
}

public fun <T : Comparable<T>> Set<T>.minOrNull(): T? {
    var best: T? = null
    for (element in this) {
        val current = best
        if (current == null || current.compareTo(element) > 0) best = element
    }
    return best
}

public fun <T> Set<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        result.add(element)
    }
    return result
}
