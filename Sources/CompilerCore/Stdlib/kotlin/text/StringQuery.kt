package kotlin.text

// KSP-402
// String query helpers migrated from Swift runtime entry points.

public fun String.first(): Char {
    if (isEmpty()) {
        throw NoSuchElementException("Char sequence is empty.")
    }
    return toCharArray()[0]
}

public fun String.first(predicate: (Char) -> Boolean): Char {
    val chars = toCharArray()
    var foundIndex = -1
    var i = 0
    val sz = chars.size
    while (i < sz && foundIndex < 0) {
        if (predicate(chars[i])) {
            foundIndex = i
        }
        i += 1
    }
    if (foundIndex >= 0) return chars[foundIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.firstOrNull(): Char? {
    val chars = toCharArray()
    if (chars.isEmpty()) {
        return null
    }
    return chars[0]
}

public fun String.firstOrNull(predicate: (Char) -> Boolean): Char? {
    val chars = toCharArray()
    var foundIndex = -1
    var i = 0
    val sz = chars.size
    while (i < sz && foundIndex < 0) {
        if (predicate(chars[i])) {
            foundIndex = i
        }
        i += 1
    }
    if (foundIndex >= 0) return chars[foundIndex]
    return null
}

public fun String.last(): Char {
    val chars = toCharArray()
    if (chars.isEmpty()) {
        throw NoSuchElementException("Char sequence is empty.")
    }
    return chars[chars.lastIndex]
}

public fun String.last(predicate: (Char) -> Boolean): Char {
    val chars = toCharArray()
    var foundIndex = -1
    var i = chars.lastIndex
    while (i >= 0 && foundIndex < 0) {
        if (predicate(chars[i])) {
            foundIndex = i
        }
        i -= 1
    }
    if (foundIndex >= 0) return chars[foundIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.lastOrNull(): Char? {
    val chars = toCharArray()
    if (chars.isEmpty()) return null
    return chars[chars.lastIndex]
}

public fun String.lastOrNull(predicate: (Char) -> Boolean): Char? {
    val chars = toCharArray()
    var foundIndex = -1
    var i = chars.lastIndex
    while (i >= 0 && foundIndex < 0) {
        if (predicate(chars[i])) {
            foundIndex = i
        }
        i -= 1
    }
    if (foundIndex >= 0) return chars[foundIndex]
    return null
}

public fun String.single(): Char {
    val chars = toCharArray()
    val sz = chars.size
    if (sz == 1) return chars[0]
    if (sz == 0) throw NoSuchElementException("Char sequence is empty.")
    throw IllegalArgumentException("Char sequence has more than one element.")
}

public fun String.single(predicate: (Char) -> Boolean): Char {
    val chars = toCharArray()
    var matchIndex = -1
    var hasMultipleMatches = false
    var i = 0
    val sz = chars.size
    while (i < sz) {
        if (predicate(chars[i])) {
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
    if (matchIndex >= 0) return chars[matchIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.singleOrNull(): Char? {
    val chars = toCharArray()
    if (chars.size == 1) return chars[0]
    return null
}

public fun String.singleOrNull(predicate: (Char) -> Boolean): Char? {
    val chars = toCharArray()
    var matchIndex = -1
    var hasMultipleMatches = false
    var i = 0
    val sz = chars.size
    while (i < sz) {
        if (predicate(chars[i])) {
            if (matchIndex >= 0) {
                hasMultipleMatches = true
            } else {
                matchIndex = i
            }
        }
        i += 1
    }
    if (!hasMultipleMatches && matchIndex >= 0) return chars[matchIndex]
    return null
}

public fun String.getOrNull(index: Int): Char? {
    val chars = toCharArray()
    if (index < 0 || index >= chars.size) return null
    return chars[index]
}
