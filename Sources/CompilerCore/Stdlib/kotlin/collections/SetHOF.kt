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
