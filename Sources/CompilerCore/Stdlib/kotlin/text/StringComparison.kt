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

// KSP-413: compareTo(ignoreCase) / contentEquals / equals(ignoreCase) moved off the
// Swift runtime.
//
// The flat String aggregate stores UTF-8 byte length, while Kotlin indexing is
// character-based, so `length`/`this[i]` walk past non-ASCII input. Character
// traversal goes through `toString().toList()` (see StringPrefixSuffix.kt).
//
// Case folding follows the two-step rule of `String.compareToIgnoreCase` and
// `Char.equals(other, ignoreCase = true)`: compare the upper-cased characters
// first, then their lower-cased forms, so that alphabets whose case mapping is
// not a bijection still compare equal.

private fun ksp413FoldedCompare(a: Char, b: Char): Int {
    if (a == b) return 0
    val upperA = a.uppercaseChar()
    val upperB = b.uppercaseChar()
    if (upperA == upperB) return 0
    val lowerA = upperA.lowercaseChar()
    val lowerB = upperB.lowercaseChar()
    if (lowerA == lowerB) return 0
    return lowerA.code - lowerB.code
}

private fun ksp413CharsEqualIgnoreCase(a: Char, b: Char): Boolean = ksp413FoldedCompare(a, b) == 0

private fun ksp413ContentEquals(self: List<Char>, other: List<Char>, ignoreCase: Boolean): Boolean {
    if (self.size != other.size) return false
    var index = 0
    while (index < self.size) {
        val a = self[index]
        val b = other[index]
        if (a != b && !(ignoreCase && ksp413CharsEqualIgnoreCase(a, b))) return false
        index++
    }
    return true
}

/**
 * Compares two strings lexicographically, optionally ignoring character case.
 *
 * Returns a negative number, zero or a positive number when this string sorts
 * before, equal to or after [other] respectively.
 */
public fun String.compareTo(other: String, ignoreCase: Boolean): Int {
    val selfChars = this.toList()
    val otherChars = other.toList()
    val shared = minOf(selfChars.size, otherChars.size)
    var index = 0
    while (index < shared) {
        val a = selfChars[index]
        val b = otherChars[index]
        if (a != b) {
            if (!ignoreCase) return a.code - b.code
            val difference = ksp413FoldedCompare(a, b)
            if (difference != 0) return difference
        }
        index++
    }
    return selfChars.size - otherChars.size
}

/**
 * Returns `true` if this char sequence and [other] contain the same characters
 * in the same order, or if both are `null`.
 */
public fun CharSequence?.contentEquals(other: CharSequence?): Boolean {
    val value = this
    if (value == null) return other == null
    if (other == null) return false
    return ksp413ContentEquals(value!!.toString().toList(), other!!.toString().toList(), false)
}

/**
 * Returns `true` if this char sequence and [other] contain the same characters
 * in the same order, or if both are `null`.
 *
 * @param ignoreCase `true` to ignore character case when comparing characters.
 */
public fun CharSequence?.contentEquals(other: CharSequence?, ignoreCase: Boolean): Boolean {
    val value = this
    if (value == null) return other == null
    if (other == null) return false
    return ksp413ContentEquals(value!!.toString().toList(), other!!.toString().toList(), ignoreCase)
}

/**
 * Returns `true` if this string is equal to [other], optionally ignoring character case.
 */
public fun String?.equals(other: String?, ignoreCase: Boolean): Boolean {
    val value = this
    if (value == null) return other == null
    if (other == null) return false
    if (!ignoreCase) return value == other
    return ksp413ContentEquals(value!!.toList(), other!!.toList(), true)
}

/**
 * Compares this string with [other] using the collation rules of [locale].
 *
 * Locale-aware collation stays in the runtime (`__kk_string_compareTo_locale`).
 */
public fun String.compareTo(other: String, locale: java.util.Locale): Int =
    this.__kk_string_compareTo_locale(other, locale)
