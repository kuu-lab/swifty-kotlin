package kotlin.text

// String comparison functions migrated from Swift Runtime
// MIGRATION-TEXT-009

/**
 * Returns the longest common prefix of this string and the specified [other] string.
 *
 * @param other The string to compare with.
 * @param ignoreCase `true` to ignore character case when comparing. By default `false`.
 * @return The longest common prefix.
 */
public fun String.commonPrefixWith(other: String, ignoreCase: Boolean = false): String {
    val shortestLength = minOf(this.length, other.length)
    var i = 0
    while (i < shortestLength) {
        if (!charsEqual(this[i], other[i], ignoreCase)) break
        i++
    }
    if (i == 0) return ""
    if (i == this.length) return this
    return this.substring(0, i)
}

/**
 * Returns the longest common suffix of this string and the specified [other] string.
 *
 * @param other The string to compare with.
 * @param ignoreCase `true` to ignore character case when comparing. By default `false`.
 * @return The longest common suffix.
 */
public fun String.commonSuffixWith(other: String, ignoreCase: Boolean = false): String {
    val shortestLength = minOf(this.length, other.length)
    var i = 0
    while (i < shortestLength) {
        if (!charsEqual(this[this.length - 1 - i], other[other.length - 1 - i], ignoreCase)) break
        i++
    }
    if (i == 0) return ""
    if (i == this.length) return this
    return this.substring(this.length - i)
}

// Helper function to compare characters with optional case-insensitivity
private fun charsEqual(a: Char, b: Char, ignoreCase: Boolean): Boolean {
    if (!ignoreCase) {
        return a == b
    }
    // Case-insensitive comparison using lowercase
    return a.lowercaseChar() == b.lowercaseChar()
}
