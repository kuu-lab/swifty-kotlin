package kotlin.text

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
