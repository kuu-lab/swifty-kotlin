package kotlin.collections

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
