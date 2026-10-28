package kotlin.text

// String operations traverse toString().toList(); CharSequence slice keeps
// indexed access on the receiver so custom implementations remain observable.

private fun buildStringFromCharRange(chars: List<Char>, startIndex: Int, endIndex: Int): String {
    val sb = StringBuilder()
    // Append the collected range once so UTF-16 surrogate pairs stay intact.
    val range = CharArray(endIndex - startIndex)
    var i = startIndex
    while (i < endIndex) {
        range[i - startIndex] = chars[i]
        i++
    }
    sb.appendRange(range, 0, range.size)
    return sb.toString()
}

public fun String.substring(startIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length) {
        throw java.lang.StringIndexOutOfBoundsException(
            "Range [$startIndex, $length) out of bounds for length $length"
        )
    }
    return buildStringFromCharRange(chars, startIndex, length)
}

public fun String.substring(startIndex: Int, endIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw java.lang.StringIndexOutOfBoundsException(
            "Range [$startIndex, $endIndex) out of bounds for length $length"
        )
    }
    return buildStringFromCharRange(chars, startIndex, endIndex)
}

@kotlin.internal.InlineOnly
public inline fun CharSequence.substring(startIndex: Int, endIndex: Int = length): String =
    this.subSequence(startIndex, endIndex).toString()

public fun CharSequence.substring(range: IntRange): String =
    this.subSequence(range.start, range.endInclusive + 1).toString()

@Deprecated(
    "Use substring(startIndex, endIndex) instead.",
    ReplaceWith("substring(startIndex, endIndex)")
)
public fun String.subSequence(startIndex: Int, endIndex: Int): String =
    this.substring(startIndex, endIndex)

// KSP-1402: delegates to the nominal two-argument member so custom receivers
// keep their own `subSequence` behavior and UTF-16 indices.
public fun CharSequence.subSequence(range: IntRange): CharSequence =
    this.subSequence(range.start, range.endInclusive + 1)

public fun String.slice(indices: IntRange): String {
    if (indices.isEmpty()) return ""
    return this.substring(indices.first, indices.last + 1)
}

public fun String.slice(indices: Iterable<Int>): String {
    val chars = this.toString().toList()
    val length = chars.size
    val sb = StringBuilder()
    for (index in indices) {
        if (index < 0 || index >= length) {
            throw java.lang.StringIndexOutOfBoundsException(
                "Index $index out of bounds for length $length"
            )
        }
        sb.append(chars[index])
    }
    return sb.toString()
}

public fun CharSequence.slice(indices: IntRange): CharSequence {
    if (indices.isEmpty()) return ""
    return this.subSequence(indices.first, indices.last + 1)
}

public fun CharSequence.slice(indices: Iterable<Int>): CharSequence {
    val size = if (indices is Collection<*>) indices.size else 10
    if (size == 0) return ""
    val chars = mutableListOf<Char>()
    for (index in indices) {
        chars.add(get(index))
    }
    val result = StringBuilder(size)
    // Append the collected UTF-16 code units in one bridge call so surrogate
    // pairs are preserved by the native StringBuilder representation.
    return result.appendRange(chars.toCharArray(), 0, chars.size)
}

public fun String.removeRange(startIndex: Int, endIndex: Int): String {
    // JVM delegates to CharSequence.removeRange, which checks reversed ranges
    // first, short-circuits empty removals before any bounds check, and lets the
    // negative StringBuilder capacity surface as NegativeArraySizeException.
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End index ($endIndex) is less than start index ($startIndex).")
    }
    if (endIndex == startIndex) {
        return this
    }
    val chars = this.toString().toList()
    val length = chars.size
    val sb = StringBuilder(length - (endIndex - startIndex))
    if (startIndex < 0 || startIndex > length) {
        throw IndexOutOfBoundsException("Range [0, $startIndex) out of bounds for length $length")
    }
    if (endIndex > length) {
        throw IndexOutOfBoundsException("Range [$endIndex, $length) out of bounds for length $length")
    }
    sb.append(buildStringFromCharRange(chars, 0, startIndex))
    sb.append(buildStringFromCharRange(chars, endIndex, length))
    return sb.toString()
}

public fun String.removeRange(range: IntRange): String =
    this.removeRange(range.first, range.last + 1)

public fun String.replaceRange(startIndex: Int, endIndex: Int, replacement: CharSequence): String {
    // JVM appends through StringBuilder(CharSequence, start, end): the reversed
    // range check runs first, then the start bound, then the end bound.
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End index ($endIndex) is less than start index ($startIndex).")
    }
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length) {
        throw IndexOutOfBoundsException("Range [0, $startIndex) out of bounds for length $length")
    }
    if (endIndex > length) {
        throw IndexOutOfBoundsException("Range [$endIndex, $length) out of bounds for length $length")
    }
    val sb = StringBuilder()
    sb.append(buildStringFromCharRange(chars, 0, startIndex))
    sb.append(replacement.toString())
    sb.append(buildStringFromCharRange(chars, endIndex, length))
    return sb.toString()
}

public fun String.replaceRange(range: IntRange, replacement: CharSequence): String =
    this.replaceRange(range.first, range.last + 1, replacement)
