package kotlin.text

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

public fun CharSequence.startsWith(prefix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return __kkRegionMatches(selfChars, 0, prefixChars, 0, prefixChars.size, ignoreCase)
}

public fun CharSequence.startsWith(prefix: CharSequence, startIndex: Int, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return __kkRegionMatches(selfChars, startIndex, prefixChars, 0, prefixChars.size, ignoreCase)
}

public fun CharSequence.startsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && __kkCharsEqual(selfChars[0], char, ignoreCase)
}

public fun CharSequence.endsWith(suffix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val suffixChars = suffix.toString().toList()
    return __kkRegionMatches(selfChars, selfChars.size - suffixChars.size, suffixChars, 0, suffixChars.size, ignoreCase)
}

public fun CharSequence.endsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && __kkCharsEqual(selfChars[selfChars.size - 1], char, ignoreCase)
}

public fun String.removePrefix(prefix: CharSequence): String {
    if (startsWith(prefix)) {
        return this.substring(prefix.toString().toList().size)
    }
    return this
}

public fun String.removeSuffix(suffix: CharSequence): String {
    if (endsWith(suffix)) {
        val selfLength = this.toList().size
        return this.substring(0, selfLength - suffix.toString().toList().size)
    }
    return this
}

public fun String.removeSurrounding(prefix: CharSequence, suffix: CharSequence): String {
    val selfLength = this.toList().size
    val prefixLength = prefix.toString().toList().size
    val suffixLength = suffix.toString().toList().size
    if (selfLength >= prefixLength + suffixLength && startsWith(prefix) && endsWith(suffix)) {
        return this.substring(prefixLength, selfLength - suffixLength)
    }
    return this
}

public fun String.removeSurrounding(delimiter: CharSequence): String = removeSurrounding(delimiter, delimiter)

// KSP-1393: CharSequence remove-family overloads are source-backed with the
// Kotlin 2.3.10 CharSequence return contract. Keep them separate from the
// String overloads so static CharSequence receivers preserve indexed dispatch.

public fun CharSequence.removePrefix(prefix: CharSequence): CharSequence {
    if (__kkCharSequenceRegionMatches(this, 0, prefix, 0, prefix.length, false)) {
        return this.subSequence(prefix.length, length)
    }
    return this.subSequence(0, length)
}

public fun CharSequence.removeSuffix(suffix: CharSequence): CharSequence {
    if (__kkCharSequenceRegionMatches(this, length - suffix.length, suffix, 0, suffix.length, false)) {
        return this.subSequence(0, length - suffix.length)
    }
    return this.subSequence(0, length)
}

public fun CharSequence.removeSurrounding(prefix: CharSequence, suffix: CharSequence): CharSequence {
    if (length >= prefix.length + suffix.length &&
        __kkCharSequenceRegionMatches(this, 0, prefix, 0, prefix.length, false) &&
        __kkCharSequenceRegionMatches(this, length - suffix.length, suffix, 0, suffix.length, false)
    ) {
        return this.subSequence(prefix.length, length - suffix.length)
    }
    return this.subSequence(0, length)
}

public fun CharSequence.removeSurrounding(delimiter: CharSequence): CharSequence =
    removeSurrounding(delimiter, delimiter)

// KSP-1393: Keep the two overloads separate from String.removeRange so static
// CharSequence receivers select the Kotlin 2.3.10 contract and preserve indexed
// CharSequence dispatch.
public fun CharSequence.removeRange(startIndex: Int, endIndex: Int): CharSequence {
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End index ($endIndex) is less than start index ($startIndex).")
    }

    if (endIndex == startIndex) {
        return this.subSequence(0, length)
    }

    // JVM allocates the destination builder before appending, so an oversized
    // removed span surfaces as NegativeArraySizeException ahead of the range
    // checks on the two appends below. Read `length` once here: JVM evaluates
    // it only for the capacity and the final append bound, so the bounds
    // checks must not add observable reads on custom receivers.
    val currentLength = length
    val sb = StringBuilder(currentLength - (endIndex - startIndex))
    if (startIndex < 0 || startIndex > currentLength) {
        throw IndexOutOfBoundsException("Range [0, $startIndex) out of bounds for length $currentLength")
    }
    if (endIndex > currentLength) {
        throw IndexOutOfBoundsException("Range [$endIndex, $currentLength) out of bounds for length $currentLength")
    }

    // Use StringBuilder's CharSequence-aware appendRange so custom receivers
    // retain indexed UTF-16 dispatch and the stable bridge's range checks.
    sb.appendRange(this, 0, startIndex)
    sb.appendRange(this, endIndex, length)
    return sb
}

public fun CharSequence.removeRange(range: IntRange): CharSequence =
    removeRange(range.start, range.endInclusive + 1)
