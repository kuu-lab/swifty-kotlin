package kotlin.text

// KSP-402
// String query helpers migrated from Swift runtime entry points.

public fun String.first(): Char {
    if (length == 0) {
        throw NoSuchElementException("Char sequence is empty.")
    }
    return this[0]
}

public fun String.first(predicate: (Char) -> Boolean): Char {
    var foundIndex = -1
    var i = 0
    val sz = length
    while (i < sz && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i += 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.firstOrNull(): Char? {
    if (length == 0) {
        return null
    }
    return this[0]
}

public fun String.firstOrNull(predicate: (Char) -> Boolean): Char? {
    var foundIndex = -1
    var i = 0
    val sz = length
    while (i < sz && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i += 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    return null
}

public fun String.last(): Char {
    val sz = length
    if (sz == 0) {
        throw NoSuchElementException("Char sequence is empty.")
    }
    return this[sz - 1]
}

public fun String.last(predicate: (Char) -> Boolean): Char {
    var foundIndex = -1
    var i = length - 1
    while (i >= 0 && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i -= 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.lastOrNull(): Char? {
    val sz = length
    if (sz == 0) return null
    return this[sz - 1]
}

public fun String.lastOrNull(predicate: (Char) -> Boolean): Char? {
    var foundIndex = -1
    var i = length - 1
    while (i >= 0 && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i -= 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    return null
}

public fun String.single(): Char {
    val sz = length
    if (sz == 1) return this[0]
    if (sz == 0) throw NoSuchElementException("Char sequence is empty.")
    throw IllegalArgumentException("Char sequence has more than one element.")
}

public fun String.single(predicate: (Char) -> Boolean): Char {
    var matchIndex = -1
    var hasMultipleMatches = false
    var i = 0
    val sz = length
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                hasMultipleMatches = true
            } else {
                matchIndex = i
            }
        }
        i += 1
    }
    if (hasMultipleMatches) {
        throw IllegalArgumentException("Char sequence contains more than one matching element.")
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.singleOrNull(): Char? {
    if (length == 1) return this[0]
    return null
}

public fun String.singleOrNull(predicate: (Char) -> Boolean): Char? {
    var matchIndex = -1
    var hasMultipleMatches = false
    var i = 0
    val sz = length
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                hasMultipleMatches = true
            } else {
                matchIndex = i
            }
        }
        i += 1
    }
    if (!hasMultipleMatches && matchIndex >= 0) return this[matchIndex]
    return null
}

public fun String.getOrNull(index: Int): Char? {
    if (index < 0 || index >= length) return null
    return this[index]
}
