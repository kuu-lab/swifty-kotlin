package kotlin.text

// KSP-663: Char サロゲート演算とコードポイント変換を bundled Kotlin 化。
// 残留ブリッジ: Char↔Int 変換 (kk_int_to_char) のみを CharConversions の
// __charFromCode 経由で再利用。

public fun Char.isSurrogate(): Boolean = this >= '\uD800' && this <= '\uDFFF'

public fun Char.isHighSurrogate(): Boolean = this >= '\uD800' && this <= '\uDBFF'

public fun Char.isLowSurrogate(): Boolean = this >= '\uDC00' && this <= '\uDFFF'

public fun CharSequence.hasSurrogatePairAt(index: Int): Boolean {
    return index >= 0
            && index <= length - 2
            && this[index].isHighSurrogate()
            && this[index + 1].isLowSurrogate()
}

@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.isSupplementaryCodePoint(codepoint: Int): Boolean =
    codepoint in 0x10000..0x10FFFF

@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.isSurrogatePair(high: Char, low: Char): Boolean =
    high.isHighSurrogate() && low.isLowSurrogate()

/** Doesn't validate that the characters are a valid surrogate pair. */
@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.toCodePoint(high: Char, low: Char): Int =
    (((high - '\uD800') shl 10) + (low - '\uDC00')) + 0x10000

@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.toChars(codePoint: Int): CharArray {
    return if (codePoint in 0x0000..0xFFFF) {
        val result = CharArray(1)
        result[0] = __charFromCode(codePoint)
        result
    } else if (codePoint in 0x10000..0x10FFFF) {
        val offset = codePoint - 0x10000
        val high = 0xD800 + (offset shr 10)
        val low = 0xDC00 + (offset and 0x3FF)
        val result = CharArray(2)
        result[0] = __charFromCode(high)
        result[1] = __charFromCode(low)
        result
    } else {
        throw IllegalArgumentException()
    }
}
