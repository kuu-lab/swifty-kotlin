package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-661: Char 判定系は純 Kotlin で実装し、Unicode テーブル参照だけを
// Swift ランタイムの 1 行ブリッジ (__kk_char_*) に残す。

/// Unicode general category ordinal (kotlin.text.CharCategory の序数と一致)。
/// サロゲートは 18 (SURROGATE)、未割り当ては 0 (UNASSIGNED) を返す。
@KsSymbolName("__kk_char_unicode_category")
internal external fun __charUnicodeCategory(code: Int): Int

@KsSymbolName("__kk_char_is_uppercase")
internal external fun __charIsUpperCase(code: Int): Boolean

@KsSymbolName("__kk_char_is_lowercase")
internal external fun __charIsLowerCase(code: Int): Boolean

private const val CATEGORY_UNASSIGNED = 0
private const val CATEGORY_UPPERCASE_LETTER = 1
private const val CATEGORY_OTHER_LETTER = 5
private const val CATEGORY_DECIMAL_DIGIT_NUMBER = 9
private const val CATEGORY_SPACE_SEPARATOR = 12
private const val CATEGORY_LINE_SEPARATOR = 13
private const val CATEGORY_PARAGRAPH_SEPARATOR = 14

public fun Char.isLetter(): Boolean {
    val category = __charUnicodeCategory(this.code)
    return category >= CATEGORY_UPPERCASE_LETTER && category <= CATEGORY_OTHER_LETTER
}

public fun Char.isDigit(): Boolean = __charUnicodeCategory(this.code) == CATEGORY_DECIMAL_DIGIT_NUMBER

public fun Char.isLetterOrDigit(): Boolean = isLetter() || isDigit()

public fun Char.isWhitespace(): Boolean {
    val code = this.code
    val category = __charUnicodeCategory(code)
    if (category == CATEGORY_SPACE_SEPARATOR ||
        category == CATEGORY_LINE_SEPARATOR ||
        category == CATEGORY_PARAGRAPH_SEPARATOR
    ) {
        return true
    }
    return code in 0x09..0x0D || code in 0x1C..0x1F
}

public fun Char.isUpperCase(): Boolean = __charIsUpperCase(this.code)

public fun Char.isLowerCase(): Boolean = __charIsLowerCase(this.code)

public fun Char.isDefined(): Boolean = __charUnicodeCategory(this.code) != CATEGORY_UNASSIGNED
