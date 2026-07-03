package kotlin.collections

// MIGRATION-COL-005
// List search HOFs migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift  (first / last / find / findLast / indexOf*)
//   Sources/Runtime/RuntimeCollections.swift    (firstOrNull / lastOrNull / single / singleOrNull)
//
// NOTE: Runtime ABI entry points are intentionally kept as bridge/compatibility
// helpers while stdlib-source dispatch is rolled out incrementally.

public fun <T> List<T>.first(): T {
    if (size == 0) throw NoSuchElementException("Collection is empty.")
    return this[0]
}

public fun <T> List<T>.first(predicate: (T) -> Boolean): T {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.firstOrNull(): T? {
    if (size == 0) return null
    return this[0]
}

public fun <T> List<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.find(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.last(): T {
    if (size == 0) throw NoSuchElementException("Collection is empty.")
    return this[size - 1]
}

public fun <T> List<T>.last(predicate: (T) -> Boolean): T {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.lastOrNull(): T? {
    if (size == 0) return null
    return this[size - 1]
}

public fun <T> List<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.findLast(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.single(): T {
    val sz = size
    if (sz == 1) return this[0]
    if (sz == 0) throw NoSuchElementException("Collection is empty.")
    throw IllegalArgumentException("Collection has more than one element.")
}

public fun <T> List<T>.single(predicate: (T) -> Boolean): T {
    var matchIndex = -1
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                throw IllegalArgumentException("Collection contains more than one matching element.")
            }
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.singleOrNull(): T? {
    if (size == 1) return this[0]
    return null
}

public fun <T> List<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var matchIndex = -1
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) return null
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    return null
}

public fun <T> List<T>.indexOf(element: T): Int {
    var i = 0
    val sz = size
    while (i < sz) {
        if (this[i] == element) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfFirst(predicate: (T) -> Boolean): Int {
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfLast(predicate: (T) -> Boolean): Int {
    var i = size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}
