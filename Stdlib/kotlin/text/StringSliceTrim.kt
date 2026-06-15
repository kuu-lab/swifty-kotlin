package kotlin.text

// String slice and trim functions migrated from Swift Runtime
// MIGRATION-TEXT-001

/**
 * Returns a string with leading and trailing whitespace removed.
 */
public fun String.trim(): String {
    var start = 0
    var end = length
    while (start < end && this[start].isWhitespace()) start++
    while (end > start && this[end - 1].isWhitespace()) end--
    return substring(start, end)
}

/**
 * Returns a string with leading and trailing characters matching [predicate] removed.
 */
public fun String.trim(predicate: (Char) -> Boolean): String {
    var start = 0
    var end = length
    while (start < end && predicate(this[start])) start++
    while (end > start && predicate(this[end - 1])) end--
    return substring(start, end)
}

/**
 * Returns a string with leading whitespace removed.
 */
public fun String.trimStart(): String {
    var i = 0
    while (i < length && this[i].isWhitespace()) i++
    return substring(i)
}

/**
 * Returns a string with leading characters matching [predicate] removed.
 */
public fun String.trimStart(predicate: (Char) -> Boolean): String {
    var i = 0
    while (i < length && predicate(this[i])) i++
    return substring(i)
}

/**
 * Returns a string with trailing whitespace removed.
 */
public fun String.trimEnd(): String {
    var i = length
    while (i > 0 && this[i - 1].isWhitespace()) i--
    return substring(0, i)
}

/**
 * Returns a string with trailing characters matching [predicate] removed.
 */
public fun String.trimEnd(predicate: (Char) -> Boolean): String {
    var i = length
    while (i > 0 && predicate(this[i - 1])) i--
    return substring(0, i)
}

/**
 * Returns a substring of this string starting from [startIndex] to the end.
 *
 * @throws IndexOutOfBoundsException if [startIndex] is negative or greater than the length of the string.
 */
public fun String.substring(startIndex: Int): String {
    if (startIndex < 0 || startIndex > length) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, length: $length")
    }
    return substring(startIndex, length)
}

/**
 * Returns a substring of this string from [startIndex] (inclusive) to [endIndex] (exclusive).
 *
 * @throws IndexOutOfBoundsException if [startIndex] or [endIndex] is out of bounds, or [startIndex] > [endIndex].
 */
public fun String.substring(startIndex: Int, endIndex: Int): String {
    if (startIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, length: $length")
    }
    val sb = StringBuilder()
    var i = startIndex
    while (i < endIndex) {
        sb.append(this[i])
        i++
    }
    return sb.toString()
}

/**
 * Returns a subsequence of this string from [startIndex] (inclusive) to [endIndex] (exclusive).
 * Equivalent to [substring].
 */
@Deprecated(
    "Use substring(startIndex, endIndex) instead.",
    ReplaceWith("substring(startIndex, endIndex)")
)
public fun String.subSequence(startIndex: Int, endIndex: Int): CharSequence =
    substring(startIndex, endIndex)

/**
 * Returns a string containing the first [n] characters.
 *
 * @throws IllegalArgumentException if [n] is negative.
 */
public fun String.take(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return ""
    if (n >= length) return this
    val sb = StringBuilder()
    var i = 0
    while (i < n) {
        sb.append(this[i])
        i++
    }
    return sb.toString()
}

/**
 * Returns a string containing the last [n] characters.
 *
 * @throws IllegalArgumentException if [n] is negative.
 */
public fun String.takeLast(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return ""
    val start = if (n >= length) 0 else length - n
    val sb = StringBuilder()
    var i = start
    while (i < length) {
        sb.append(this[i])
        i++
    }
    return sb.toString()
}

/**
 * Returns a string with the first [n] characters removed.
 *
 * @throws IllegalArgumentException if [n] is negative.
 */
public fun String.drop(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return this
    if (n >= length) return ""
    val sb = StringBuilder()
    var i = n
    while (i < length) {
        sb.append(this[i])
        i++
    }
    return sb.toString()
}

/**
 * Returns a string with the last [n] characters removed.
 *
 * @throws IllegalArgumentException if [n] is negative.
 */
public fun String.dropLast(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return this
    val end = if (n >= length) 0 else length - n
    val sb = StringBuilder()
    var i = 0
    while (i < end) {
        sb.append(this[i])
        i++
    }
    return sb.toString()
}
