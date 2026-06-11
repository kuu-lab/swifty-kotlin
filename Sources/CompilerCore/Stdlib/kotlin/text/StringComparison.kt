package kotlin.text

// String comparison functions migrated from Swift Runtime
// MIGRATION-TEXT-009 / RF-STDLIB-004

/**
 * Returns the longest string `prefix` such that this char sequence and [other] char sequence both start with this prefix,
 * taking care not to split surrogate pairs.
 * If this and [other] have no common prefix, returns the empty string.
 *
 * @param ignoreCase `true` to ignore character case when matching a prefix. By default `false`.
 */
public fun String.commonPrefixWith(other: String, ignoreCase: Boolean = false): String {
    val shortestLength = minOf(this.length, other.length)
    var i = 0
    while (i < shortestLength) {
        val c1 = this[i]
        val c2 = other[i]
        if (if (ignoreCase) c1.lowercaseChar() != c2.lowercaseChar() else c1 != c2) break
        i++
    }
    return this.substring(0, i)
}

/**
 * Returns the longest string `suffix` such that this char sequence and [other] char sequence both end with this suffix,
 * taking care not to split surrogate pairs.
 * If this and [other] have no common suffix, returns the empty string.
 *
 * @param ignoreCase `true` to ignore character case when matching a suffix. By default `false`.
 */
public fun String.commonSuffixWith(other: String, ignoreCase: Boolean = false): String {
    val shortestLength = minOf(this.length, other.length)
    var i = 0
    while (i < shortestLength) {
        val c1 = this[this.length - 1 - i]
        val c2 = other[other.length - 1 - i]
        if (if (ignoreCase) c1.lowercaseChar() != c2.lowercaseChar() else c1 != c2) break
        i++
    }
    return this.substring(this.length - i)
}
