package kotlin.text

/**
 * Returns a string with leading and trailing whitespace removed.
 */
public fun String.trim(): String {
    var start = 0
    var end = length
    while (start < end) {
        if (!this[start].isWhitespace()) break
        start++
    }
    while (end > start) {
        if (!this[end - 1].isWhitespace()) break
        end--
    }
    if (start == 0 && end == length) return this
    if (start == end) return ""
    return this.substring(start, end)
}

/**
 * Returns a string with leading and trailing characters matching [predicate] removed.
 */
public fun String.trim(predicate: (Char) -> Boolean): String {
    var start = 0
    var end = length
    while (start < end) {
        if (!predicate(this[start])) break
        start++
    }
    while (end > start) {
        if (!predicate(this[end - 1])) break
        end--
    }
    if (start == 0 && end == length) return this
    if (start == end) return ""
    return this.substring(start, end)
}

/**
 * Returns a string with leading whitespace removed.
 */
public fun String.trimStart(): String {
    var i = 0
    while (i < length) {
        if (!this[i].isWhitespace()) break
        i++
    }
    if (i == 0) return this
    if (i == length) return ""
    return this.substring(i)
}

/**
 * Returns a string with leading characters matching [predicate] removed.
 */
public fun String.trimStart(predicate: (Char) -> Boolean): String {
    var i = 0
    while (i < length) {
        if (!predicate(this[i])) break
        i++
    }
    if (i == 0) return this
    if (i == length) return ""
    return this.substring(i)
}

/**
 * Returns a string with trailing whitespace removed.
 */
public fun String.trimEnd(): String {
    var i = length
    while (i > 0) {
        if (!this[i - 1].isWhitespace()) break
        i--
    }
    if (i == length) return this
    if (i == 0) return ""
    return this.substring(0, i)
}

/**
 * Returns a string with trailing characters matching [predicate] removed.
 */
public fun String.trimEnd(predicate: (Char) -> Boolean): String {
    var i = length
    while (i > 0) {
        if (!predicate(this[i - 1])) break
        i--
    }
    if (i == length) return this
    if (i == 0) return ""
    return this.substring(0, i)
}
