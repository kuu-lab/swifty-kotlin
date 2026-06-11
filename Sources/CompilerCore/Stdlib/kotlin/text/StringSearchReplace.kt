package kotlin.text

// String search and replace functions migrated from Swift Runtime
// MIGRATION-TEXT-002

/**
 * Returns a new string obtained by replacing all occurrences of the [oldValue] substring
 * in this string with the specified [newValue] string.
 *
 * @param oldValue The substring to be replaced.
 * @param newValue The replacement string.
 * @param ignoreCase `true` to ignore character case when matching [oldValue]. Default is `false`.
 */
public fun String.replace(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    if (oldValue.isEmpty()) {
        val sb = StringBuilder()
        sb.append(newValue)
        for (i in 0 until length) {
            sb.append(this[i])
            sb.append(newValue)
        }
        return sb.toString()
    }
    val sb = StringBuilder()
    var start = 0
    while (true) {
        val idx = indexOf(oldValue, start, ignoreCase)
        if (idx == -1) {
            sb.append(substring(start))
            break
        }
        sb.append(substring(start, idx))
        sb.append(newValue)
        start = idx + oldValue.length
    }
    return sb.toString()
}

/**
 * Returns a new string obtained by replacing all occurrences of the [oldChar] character
 * in this string with the [newChar] character.
 *
 * @param oldChar The character to replace.
 * @param newChar The replacement character.
 * @param ignoreCase `true` to ignore character case. Default is `false`.
 */
public fun String.replace(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val sb = StringBuilder()
    for (i in 0 until length) {
        val c = this[i]
        if (c == oldChar || (ignoreCase && c.lowercaseChar() == oldChar.lowercaseChar())) {
            sb.append(newChar)
        } else {
            sb.append(c)
        }
    }
    return sb.toString()
}

/**
 * Returns a new string with the first occurrence of [oldValue] replaced with [newValue].
 *
 * @param oldValue The substring to replace the first occurrence of.
 * @param newValue The replacement string.
 * @param ignoreCase `true` to ignore character case when finding [oldValue]. Default is `false`.
 */
public fun String.replaceFirst(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    val idx = indexOf(oldValue, 0, ignoreCase)
    if (idx == -1) return this
    return substring(0, idx) + newValue + substring(idx + oldValue.length)
}

/**
 * Returns a new string with the characters between [startIndex] (inclusive) and [endIndex] (exclusive)
 * replaced by [replacement].
 *
 * @param startIndex The beginning (inclusive) of the replaced range.
 * @param endIndex The end (exclusive) of the replaced range.
 * @param replacement The char sequence to replace the range with.
 * @throws IndexOutOfBoundsException if [startIndex] or [endIndex] is out of range, or [startIndex] > [endIndex].
 */
public fun String.replaceRange(startIndex: Int, endIndex: Int, replacement: CharSequence): String {
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End ($endIndex) is less than start ($startIndex)")
    }
    if (startIndex < 0 || endIndex > length) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, length: $length")
    }
    return substring(0, startIndex) + replacement.toString() + substring(endIndex)
}

/**
 * Returns a new string with the characters in the given [range] replaced by [replacement].
 *
 * @param range The range of characters to replace.
 * @param replacement The char sequence to replace the range with.
 */
public fun String.replaceRange(range: IntRange, replacement: CharSequence): String =
    replaceRange(range.first, range.last + 1, replacement)

/**
 * Returns a new string with the characters between [startIndex] (inclusive) and [endIndex] (exclusive) removed.
 *
 * @param startIndex The beginning (inclusive) of the removed range.
 * @param endIndex The end (exclusive) of the removed range.
 * @throws IndexOutOfBoundsException if [startIndex] or [endIndex] is out of range, or [startIndex] > [endIndex].
 */
public fun String.removeRange(startIndex: Int, endIndex: Int): String {
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End ($endIndex) is less than start ($startIndex)")
    }
    if (startIndex < 0 || endIndex > length) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, length: $length")
    }
    return substring(0, startIndex) + substring(endIndex)
}

/**
 * Returns a new string with the characters in the given [range] removed.
 *
 * @param range The range of characters to remove.
 */
public fun String.removeRange(range: IntRange): String =
    removeRange(range.first, range.last + 1)

/**
 * If this string starts with the given [prefix], returns a copy of this string with the prefix removed.
 * Otherwise returns this string unchanged.
 *
 * @param prefix The prefix to remove.
 */
public fun String.removePrefix(prefix: CharSequence): String {
    val p = prefix.toString()
    if (startsWith(p)) return substring(p.length)
    return this
}

/**
 * If this string ends with the given [suffix], returns a copy of this string with the suffix removed.
 * Otherwise returns this string unchanged.
 *
 * @param suffix The suffix to remove.
 */
public fun String.removeSuffix(suffix: CharSequence): String {
    val s = suffix.toString()
    if (endsWith(s)) return substring(0, length - s.length)
    return this
}

/**
 * When this string has the given [prefix] and [suffix], returns a new string having both removed.
 * Otherwise returns this string unchanged.
 *
 * @param prefix The prefix to remove.
 * @param suffix The suffix to remove.
 */
public fun String.removeSurrounding(prefix: CharSequence, suffix: CharSequence): String {
    val p = prefix.toString()
    val s = suffix.toString()
    if (length >= p.length + s.length && startsWith(p) && endsWith(s)) {
        return substring(p.length, length - s.length)
    }
    return this
}

/**
 * When this string has the given [delimiter] as both prefix and suffix, returns a new string
 * having the delimiter removed from both ends. Otherwise returns this string unchanged.
 *
 * @param delimiter The delimiter to remove from both ends.
 */
public fun String.removeSurrounding(delimiter: CharSequence): String =
    removeSurrounding(delimiter, delimiter)
