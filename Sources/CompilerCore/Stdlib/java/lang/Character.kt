package java.lang

import kotlin.text.__charUnicodeCategory

/** Unicode code point operations required by native Java compatibility consumers. */
public object Character {
    public const val NON_SPACING_MARK: Byte = 6
    public const val ENCLOSING_MARK: Byte = 7
    public const val FORMAT: Byte = 16

    // Java deliberately does not validate code points for this operation.
    public fun charCount(codePoint: Int): Int = if (codePoint >= 0x10000) 2 else 1

    public fun isSpaceChar(codePoint: Int): Boolean {
        val category = getType(codePoint)
        return category >= 12 && category <= 14
    }

    public fun getType(codePoint: Int): Int {
        // The shared Unicode bridge returns Kotlin CharCategory ordinals.
        // Java leaves value 17 unused, so PRIVATE_USE and later categories shift by one.
        val ordinal = __charUnicodeCategory(codePoint)
        return if (ordinal >= 17) ordinal + 1 else ordinal
    }
}
