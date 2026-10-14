package kotlin.text

/**
 * Returns the Unicode code point starting at the UTF-16 code-unit [index].
 * A high surrogate followed by a low surrogate is combined; otherwise the
 * code unit at [index] is returned unchanged, including unpaired surrogates.
 *
 * @throws IndexOutOfBoundsException if [index] is outside this string.
 */
public fun String.codePointAt(index: Int): Int {
    // String.get preserves UTF-16 code units and throws for invalid indices.
    val first = this[index]
    if (first.isHighSurrogate() && index < length - 1) {
        val second = this[index + 1]
        if (second.isLowSurrogate()) {
            return ((first.code - 0xD800) shl 10) + (second.code - 0xDC00) + 0x10000
        }
    }
    return first.code
}
