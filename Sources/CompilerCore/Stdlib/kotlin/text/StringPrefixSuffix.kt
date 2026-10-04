package kotlin.text

// KSP-404: prefix/suffix helpers migrated from Swift Runtime.
// startsWith / endsWith / removePrefix / removeSuffix / removeSurrounding.
// The String overloads retain the flat-string-safe `toString().toList()` paths.
// CharSequence remove-family overloads use the interface's UTF-16
// length/get/subSequence operations so custom implementations keep their
// indexed dispatch.

private fun __kkCharSequenceRegionMatches(
    self: CharSequence,
    thisOffset: Int,
    other: CharSequence,
    otherOffset: Int,
    length: Int,
    ignoreCase: Boolean
): Boolean {
    if (length < 0 || thisOffset < 0 || otherOffset < 0 ||
        thisOffset > self.length - length ||
        otherOffset > other.length - length
    ) {
        return false
    }

    var index = 0
    while (index < length) {
        if (!__kkCharsEqual(self[thisOffset + index], other[otherOffset + index], ignoreCase)) {
            return false
        }
        index++
    }
    return true
}

/**
 * Returns `true` if this char sequence starts with the specified [prefix].
 */
public fun CharSequence.startsWith(prefix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return __kkRegionMatches(selfChars, 0, prefixChars, 0, prefixChars.size, ignoreCase)
}

/**
 * Returns `true` if a substring of this char sequence starting at the specified offset [startIndex]
 * starts with the specified [prefix].
 */
public fun CharSequence.startsWith(prefix: CharSequence, startIndex: Int, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return __kkRegionMatches(selfChars, startIndex, prefixChars, 0, prefixChars.size, ignoreCase)
}

/**
 * Returns `true` if this char sequence starts with the specified character.
 */
public fun CharSequence.startsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && __kkCharsEqual(selfChars[0], char, ignoreCase)
}

/**
 * Returns `true` if this char sequence ends with the specified [suffix].
 */
public fun CharSequence.endsWith(suffix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val suffixChars = suffix.toString().toList()
    return __kkRegionMatches(selfChars, selfChars.size - suffixChars.size, suffixChars, 0, suffixChars.size, ignoreCase)
}

/**
 * Returns `true` if this char sequence ends with the specified character.
 */
public fun CharSequence.endsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && __kkCharsEqual(selfChars[selfChars.size - 1], char, ignoreCase)
}

/**
 * If this string starts with the given [prefix], returns a copy of this string
 * with the prefix removed. Otherwise, returns this string.
 */
public fun String.removePrefix(prefix: CharSequence): String {
    if (startsWith(prefix)) {
        return this.substring(prefix.toString().toList().size)
    }
    return this
}

/**
 * If this string ends with the given [suffix], returns a copy of this string
 * with the suffix removed. Otherwise, returns this string.
 */
public fun String.removeSuffix(suffix: CharSequence): String {
    if (endsWith(suffix)) {
        val selfLength = this.toList().size
        return this.substring(0, selfLength - suffix.toString().toList().size)
    }
    return this
}

/**
 * When this string starts with the given [prefix] and ends with the given [suffix],
 * returns a copy of this string having both the given [prefix] and [suffix] removed.
 * Otherwise returns this string unchanged.
 */
public fun String.removeSurrounding(prefix: CharSequence, suffix: CharSequence): String {
    val selfLength = this.toList().size
    val prefixLength = prefix.toString().toList().size
    val suffixLength = suffix.toString().toList().size
    if (selfLength >= prefixLength + suffixLength && startsWith(prefix) && endsWith(suffix)) {
        return this.substring(prefixLength, selfLength - suffixLength)
    }
    return this
}

/**
 * When this string starts with and ends with the given [delimiter],
 * returns a copy of this string having the [delimiter] removed from both ends.
 * Otherwise returns this string unchanged.
 */
public fun String.removeSurrounding(delimiter: CharSequence): String = removeSurrounding(delimiter, delimiter)

// KSP-1393: CharSequence remove-family overloads are source-backed with the
// Kotlin 2.3.10 CharSequence return contract. Keep them separate from the
// String overloads so static CharSequence receivers preserve indexed dispatch.

/**
 * If this char sequence starts with the given [prefix], returns a copy of this char sequence
 * with the prefix removed. Otherwise, returns this char sequence.
 */
public fun CharSequence.removePrefix(prefix: CharSequence): CharSequence {
    if (__kkCharSequenceRegionMatches(this, 0, prefix, 0, prefix.length, false)) {
        return this.subSequence(prefix.length, length)
    }
    return this.subSequence(0, length)
}

/**
 * If this char sequence ends with the given [suffix], returns a copy of this char sequence
 * with the suffix removed. Otherwise, returns this char sequence.
 */
public fun CharSequence.removeSuffix(suffix: CharSequence): CharSequence {
    if (__kkCharSequenceRegionMatches(this, length - suffix.length, suffix, 0, suffix.length, false)) {
        return this.subSequence(0, length - suffix.length)
    }
    return this.subSequence(0, length)
}

/**
 * When this char sequence starts with the given [prefix] and ends with the given [suffix],
 * returns a copy of this char sequence having both the given [prefix] and [suffix] removed.
 * Otherwise returns this char sequence unchanged.
 */
public fun CharSequence.removeSurrounding(prefix: CharSequence, suffix: CharSequence): CharSequence {
    if (length >= prefix.length + suffix.length &&
        __kkCharSequenceRegionMatches(this, 0, prefix, 0, prefix.length, false) &&
        __kkCharSequenceRegionMatches(this, length - suffix.length, suffix, 0, suffix.length, false)
    ) {
        return this.subSequence(prefix.length, length - suffix.length)
    }
    return this.subSequence(0, length)
}

/**
 * When this char sequence starts with and ends with the given [delimiter],
 * returns a copy of this char sequence having the [delimiter] removed from both ends.
 * Otherwise returns this char sequence unchanged.
 */
public fun CharSequence.removeSurrounding(delimiter: CharSequence): CharSequence =
    removeSurrounding(delimiter, delimiter)

// KSP-1393: CharSequence.removeRange is source-backed. Keep the two overloads
// separate from String.removeRange so static CharSequence receivers select the
// Kotlin 2.3.10 contract and preserve indexed CharSequence dispatch.
public fun CharSequence.removeRange(startIndex: Int, endIndex: Int): CharSequence {
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End index ($endIndex) is less than start index ($startIndex).")
    }

    if (endIndex == startIndex) {
        return this.subSequence(0, length)
    }

    // Use StringBuilder's CharSequence-aware appendRange so custom receivers
    // retain indexed UTF-16 dispatch and the stable bridge's range checks.
    val sb = StringBuilder(length - (endIndex - startIndex))
    sb.appendRange(this, 0, startIndex)
    sb.appendRange(this, endIndex, length)
    return sb
}

public fun CharSequence.removeRange(range: IntRange): CharSequence =
    removeRange(range.start, range.endInclusive + 1)
