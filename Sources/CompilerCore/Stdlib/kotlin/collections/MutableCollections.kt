package kotlin.collections

// KSP-1503: MutableList's removal helpers are source-backed extensions. They
// delegate to the source-backed removeAt member, whose default body retains
// the runtime bridge at the storage boundary.

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeFirst(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(0)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeFirstOrNull(): T? {
    if (isEmpty()) return null
    return removeAt(0)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeLast(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(size - 1)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeLastOrNull(): T? {
    if (isEmpty()) return null
    return removeAt(size - 1)
}

// KSP-436: predicate-driven mutable list operations.
//
// Direct storage mutation stays in the `__kk_mutable_*` bridges; the functions
// below are expressed in terms of the `size` / `get` / `set` / `removeAt`
// members that reach those bridges.

/**
 * Removes all elements matching the given [predicate].
 */
public fun <T> MutableList<T>.removeIf(predicate: (T) -> Boolean): Boolean {
    var changed = false
    var index = size - 1
    while (index >= 0) {
        if (predicate(this[index])) {
            removeAt(index)
            changed = true
        }
        index -= 1
    }
    return changed
}

/**
 * Replaces each element with the result of applying [transform] to it.
 */
public fun <T> MutableList<T>.replaceAll(transform: (T) -> T) {
    var index = 0
    while (index < size) {
        this[index] = transform(this[index])
        index += 1
    }
}

/**
 * Replaces every element with the specified [value].
 */
public fun <T> MutableList<T>.fill(value: T) {
    var index = 0
    while (index < size) {
        this[index] = value
        index += 1
    }
}
