package kotlin.text

// KSP-404: prefix/suffix helpers migrated from Swift Runtime.
// startsWith / endsWith / removePrefix / removeSuffix / removeSurrounding.
//
// The flat String aggregate stores UTF-8 byte length, while Kotlin indexing is
// character-based, so `length`/`this[i]` walk past non-ASCII input. Character
// traversal goes through `toString().toList()` (see StringSearchReplace.kt).

private fun ksp404CharsEqual(a: Char, b: Char, ignoreCase: Boolean): Boolean {
    if (a == b) return true
    if (!ignoreCase) return false
    return a.lowercaseChar() == b.lowercaseChar()
}

private fun ksp404RegionMatches(
    self: List<Char>,
    thisOffset: Int,
    other: List<Char>,
    otherOffset: Int,
    length: Int,
    ignoreCase: Boolean
): Boolean {
    if (otherOffset < 0 || thisOffset < 0 ||
        thisOffset > self.size - length ||
        otherOffset > other.size - length
    ) {
        return false
    }
    var index = 0
    while (index < length) {
        if (!ksp404CharsEqual(self[thisOffset + index], other[otherOffset + index], ignoreCase)) {
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
    return ksp404RegionMatches(selfChars, 0, prefixChars, 0, prefixChars.size, ignoreCase)
}

/**
 * Returns `true` if a substring of this char sequence starting at the specified offset [startIndex]
 * starts with the specified [prefix].
 */
public fun CharSequence.startsWith(prefix: CharSequence, startIndex: Int, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return ksp404RegionMatches(selfChars, startIndex, prefixChars, 0, prefixChars.size, ignoreCase)
}

/**
 * Returns `true` if this char sequence starts with the specified character.
 */
public fun CharSequence.startsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && ksp404CharsEqual(selfChars[0], char, ignoreCase)
}

/**
 * Returns `true` if this char sequence ends with the specified [suffix].
 */
public fun CharSequence.endsWith(suffix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val suffixChars = suffix.toString().toList()
    return ksp404RegionMatches(selfChars, selfChars.size - suffixChars.size, suffixChars, 0, suffixChars.size, ignoreCase)
}

/**
 * Returns `true` if this char sequence ends with the specified character.
 */
public fun CharSequence.endsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && ksp404CharsEqual(selfChars[selfChars.size - 1], char, ignoreCase)
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
