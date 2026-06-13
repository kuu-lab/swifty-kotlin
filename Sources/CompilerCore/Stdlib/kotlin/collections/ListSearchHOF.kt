package kotlin.collections

// List search HOF migrated from Swift Runtime
// MIGRATION-COL-005

public fun <T> List<T>.first(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return get(0)
}

public fun <T> List<T>.first(predicate: (T) -> Boolean): T {
    var i = 0
    while (i < size) {
        val element = get(i)
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.firstOrNull(): T? {
    return if (isEmpty()) null else get(0)
}

public fun <T> List<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    var i = 0
    while (i < size) {
        val element = get(i)
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.last(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return get(size - 1)
}

public fun <T> List<T>.last(predicate: (T) -> Boolean): T {
    var i = size - 1
    while (i >= 0) {
        val element = get(i)
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.lastOrNull(): T? {
    return if (isEmpty()) null else get(size - 1)
}

public fun <T> List<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = get(i)
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.single(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    if (size != 1) throw IllegalArgumentException("List has more than one element.")
    return get(0)
}

public fun <T> List<T>.singleOrNull(): T? {
    return if (size == 1) get(0) else null
}

public fun <T> List<T>.find(predicate: (T) -> Boolean): T? = firstOrNull(predicate)

public fun <T> List<T>.findLast(predicate: (T) -> Boolean): T? = lastOrNull(predicate)

public fun <T> List<T>.indexOf(element: T): Int {
    var i = 0
    while (i < size) {
        if (get(i) == element) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfFirst(predicate: (T) -> Boolean): Int {
    var i = 0
    while (i < size) {
        if (predicate(get(i))) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfLast(predicate: (T) -> Boolean): Int {
    var lastIdx = -1
    var i = 0
    while (i < size) {
        if (predicate(get(i))) lastIdx = i
        i++
    }
    return lastIdx
}
