package kotlin.collections

// Set HOF implementations migrated from Swift Runtime
// MIGRATION-COL-013

/**
 * Returns a list containing only elements matching the given [predicate].
 */
fun <T> Set<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

/**
 * Returns a list containing the results of applying the given [transform] function
 * to each element in the original set.
 */
fun <T, R> Set<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        result.add(transform(element))
    }
    return result
}

/**
 * Returns a single list of all elements yielded from results of [transform] function
 * being invoked on each element of original set.
 */
fun <T, R> Set<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        for (subElement in transform(element)) {
            result.add(subElement)
        }
    }
    return result
}

/**
 * Performs the given [action] on each element.
 */
fun <T> Set<T>.forEach(action: (T) -> Unit) {
    for (element in this) {
        action(element)
    }
}

/**
 * Returns the number of elements matching the given [predicate].
 */
fun <T> Set<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    for (element in this) {
        if (predicate(element)) count++
    }
    return count
}

/**
 * Returns `true` if the set has at least one element.
 */
public fun <T> Set<T>.any(): Boolean = size > 0

/**
 * Returns `true` if the set has no elements.
 */
public fun <T> Set<T>.none(): Boolean = size == 0

/**
 * Returns `true` if at least one element matches the given [predicate].
 */
fun <T> Set<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

/**
 * Returns `true` if all elements match the given [predicate].
 */
fun <T> Set<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

/**
 * Returns `true` if no elements match the given [predicate].
 */
fun <T> Set<T>.none(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return false
    }
    return true
}

/**
 * Accumulates value starting with [initial] and applying [operation] from left to right.
 */
public inline fun <T, R> Set<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    for (element in this) {
        accumulator = operation(accumulator, element)
    }
    return accumulator
}

/**
 * Accumulates value starting with [initial] and applying [operation] from left to right with element index.
 */
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

/**
 * Returns a list containing all elements not matching the given [predicate].
 */
public fun <T> Set<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) result.add(element)
    }
    return result
}

/**
 * Returns a list containing only the non-null results of applying [transform].
 */
public fun <T, R : Any> Set<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val transformed = transform(element)
        if (transformed != null) result.add(transformed)
    }
    return result
}

// --- Element access ----------------------------------------------------------

/**
 * Returns the first element, or throws if the set is empty.
 */
public fun <T> Set<T>.first(): T {
    for (element in this) {
        return element
    }
    throw NoSuchElementException("Collection is empty.")
}

/**
 * Returns the first element, or `null` if the set is empty.
 */
public fun <T> Set<T>.firstOrNull(): T? {
    for (element in this) {
        return element
    }
    return null
}

/**
 * Returns the last element, or throws if the set is empty.
 */
public fun <T> Set<T>.last(): T {
    var found = false
    var result: T? = null
    for (element in this) {
        result = element
        found = true
    }
    if (!found) throw NoSuchElementException("Collection is empty.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

/**
 * Returns the last element, or `null` if the set is empty.
 */
public fun <T> Set<T>.lastOrNull(): T? {
    var result: T? = null
    for (element in this) {
        result = element
    }
    return result
}

/**
 * Returns the single element, or `null` if the set is empty or has more than one element.
 */
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

/**
 * Returns `true` if every element of [elements] is contained in this set.
 */
public fun <T> Set<T>.containsAll(elements: Collection<out T>): Boolean {
    for (element in elements) {
        if (!this.contains(element)) return false
    }
    return true
}

// --- Set operations ----------------------------------------------------------

/**
 * Returns a set containing all elements that are contained by both this set and [other].
 */
public infix fun <T> Set<T>.intersect(other: Collection<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        if (other.contains(element)) result.add(element)
    }
    return result
}

/**
 * Returns a set containing all elements of this set and then all elements of [other].
 */
public infix fun <T> Set<T>.union(other: Collection<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        result.add(element)
    }
    for (element in other) {
        result.add(element)
    }
    return result
}

/**
 * Returns a set containing all elements of this set except those contained in [other].
 */
public infix fun <T> Set<T>.subtract(other: Collection<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        if (!other.contains(element)) result.add(element)
    }
    return result
}

// --- Ordering / extrema ------------------------------------------------------

/**
 * Returns a list of all elements sorted according to their natural sort order.
 */
public fun <T : Comparable<T>> Set<T>.sorted(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) > 0) {
            insertAt -= 1
        }
        result.add(insertAt, element)
    }
    return result
}

/**
 * Returns a list of all elements sorted descending according to their natural sort order.
 */
public fun <T : Comparable<T>> Set<T>.sortedDescending(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) < 0) {
            insertAt -= 1
        }
        result.add(insertAt, element)
    }
    return result
}

/**
 * Returns the largest element, or `null` if the set is empty.
 */
public fun <T : Comparable<T>> Set<T>.maxOrNull(): T? {
    var best: T? = null
    for (element in this) {
        val current = best
        if (current == null || element.compareTo(current) > 0) best = element
    }
    return best
}

/**
 * Returns the smallest element, or `null` if the set is empty.
 */
public fun <T : Comparable<T>> Set<T>.minOrNull(): T? {
    var best: T? = null
    for (element in this) {
        val current = best
        if (current == null || element.compareTo(current) < 0) best = element
    }
    return best
}

// --- Conversions -------------------------------------------------------------

/**
 * Returns a list containing all elements of this set.
 */
public fun <T> Set<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        result.add(element)
    }
    return result
}

/**
 * Returns a mutable list containing all elements of this set.
 */
public fun <T> Set<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        result.add(element)
    }
    return result
}

/**
 * Returns a new read-only set containing all elements of this set.
 */
public fun <T> Set<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        result.add(element)
    }
    return result
}

/**
 * Returns a new mutable set containing all elements of this set.
 */
public fun <T> Set<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) {
        result.add(element)
    }
    return result
}
