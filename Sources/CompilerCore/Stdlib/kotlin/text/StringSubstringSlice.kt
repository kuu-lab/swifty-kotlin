package kotlin.text

// KSP-406: substring / subSequence / slice / removeRange / replaceRange.
// Character indices traverse toString().toList() because a flat String's
// `length` observes UTF-8 byte length rather than the character count.

private fun ksp406Slice(chars: List<Char>, startIndex: Int, endIndex: Int): String {
    val sb = StringBuilder()
    var i = startIndex
    while (i < endIndex) {
        sb.append(chars[i])
        i++
    }
    return sb.toString()
}

public fun String.substring(startIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length) {
        throw IndexOutOfBoundsException("begin $startIndex, end $length, length $length")
    }
    return ksp406Slice(chars, startIndex, length)
}

public fun String.substring(startIndex: Int, endIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("begin $startIndex, end $endIndex, length $length")
    }
    return ksp406Slice(chars, startIndex, endIndex)
}

@Deprecated(
    "Use substring(startIndex, endIndex) instead.",
    ReplaceWith("substring(startIndex, endIndex)")
)
public fun String.subSequence(startIndex: Int, endIndex: Int): String =
    this.substring(startIndex, endIndex)

public fun String.slice(indices: IntRange): String {
    if (indices.isEmpty()) return ""
    return this.substring(indices.first, indices.last + 1)
}

public fun String.slice(indices: Iterable<Int>): String {
    val chars = this.toString().toList()
    val length = chars.size
    val sb = StringBuilder()
    // Explicit iterator rather than `for (index in indices)`: iterating an
    // Iterable-typed value misroutes to the range-iterator intrinsics (BUG-154).
    val iterator = indices.iterator()
    while (iterator.hasNext()) {
        val index = iterator.next()
        if (index < 0 || index >= length) {
            throw IndexOutOfBoundsException("index $index out of range [0, $length)")
        }
        sb.append(chars[index])
    }
    return sb.toString()
}

public fun String.removeRange(startIndex: Int, endIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length || endIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("start=$startIndex, end=$endIndex, length=$length")
    }
    val sb = StringBuilder()
    sb.append(ksp406Slice(chars, 0, startIndex))
    sb.append(ksp406Slice(chars, endIndex, length))
    return sb.toString()
}

public fun String.removeRange(range: IntRange): String =
    this.removeRange(range.first, range.last + 1)

public fun String.replaceRange(startIndex: Int, endIndex: Int, replacement: CharSequence): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length || endIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("start=$startIndex, end=$endIndex, length=$length")
    }
    val sb = StringBuilder()
    sb.append(ksp406Slice(chars, 0, startIndex))
    sb.append(replacement)
    sb.append(ksp406Slice(chars, endIndex, length))
    return sb.toString()
}

public fun String.replaceRange(range: IntRange, replacement: CharSequence): String =
    this.replaceRange(range.first, range.last + 1, replacement)
