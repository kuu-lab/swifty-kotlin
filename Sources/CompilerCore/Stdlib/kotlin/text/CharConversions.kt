package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-662: Implement Char conversions in Kotlin and retain only one-line Swift
// bridges (__kk_char_*) for Unicode case-mapping data and locale-aware conversions.

/// Full Unicode uppercase mapping, including multi-scalar mappings such as ß -> "SS".
@KsSymbolName("__kk_char_uppercase_string")
internal external fun __charUppercaseString(code: Int): String

/// Full Unicode lowercase mapping.
@KsSymbolName("__kk_char_lowercase_string")
internal external fun __charLowercaseString(code: Int): String

/// Full Unicode titlecase mapping.
@KsSymbolName("__kk_char_titlecase_string")
internal external fun __charTitlecaseString(code: Int): String

/// One-to-one uppercase mapping; returns -1 for multi-scalar or undefined mappings.
@KsSymbolName("__kk_char_uppercase_code")
internal external fun __charUppercaseCode(code: Int): Int

/// One-to-one lowercase mapping; returns -1 for undefined mappings.
@KsSymbolName("__kk_char_lowercase_code")
internal external fun __charLowercaseCode(code: Int): Int

/// One-to-one titlecase mapping; returns -1 for multi-scalar or undefined mappings.
@KsSymbolName("__kk_char_titlecase_code")
internal external fun __charTitlecaseCode(code: Int): Int

/// Equivalent to kotlin.text.digitOf before applying the radix bound; returns -1 for non-digits.
@KsSymbolName("__kk_char_digit_value")
internal external fun __charDigitValue(code: Int): Int

@KsSymbolName("__kk_char_uppercase_locale")
internal external fun __charUppercaseLocale(code: Int, locale: java.util.Locale): String

@KsSymbolName("__kk_char_lowercase_locale")
internal external fun __charLowercaseLocale(code: Int, locale: java.util.Locale): String

/// Builds a Char from a code point by reusing the existing Int.toChar() conversion.
@KsSymbolName("kk_int_to_char")
internal external fun __charFromCode(code: Int): Char

private const val CHAR_CODE_ZERO = 48 // '0'
private const val CHAR_CODE_UPPER_A = 65 // 'A'

public fun Char.uppercase(): String = __charUppercaseString(this.code)

public fun Char.lowercase(): String = __charLowercaseString(this.code)

public fun Char.titlecase(): String = __charTitlecaseString(this.code)

public fun Char.uppercase(locale: java.util.Locale): String = __charUppercaseLocale(this.code, locale)

public fun Char.lowercase(locale: java.util.Locale): String = __charLowercaseLocale(this.code, locale)

public fun Char.uppercaseChar(): Char {
    val mapped = __charUppercaseCode(this.code)
    return if (mapped < 0) this else __charFromCode(mapped)
}

public fun Char.lowercaseChar(): Char {
    val mapped = __charLowercaseCode(this.code)
    return if (mapped < 0) this else __charFromCode(mapped)
}

public fun Char.titlecaseChar(): Char {
    val mapped = __charTitlecaseCode(this.code)
    return if (mapped < 0) uppercaseChar() else __charFromCode(mapped)
}

public fun Char.digitToInt(): Int = digitToInt(10)

public fun Char.digitToInt(radix: Int): Int {
    val digit = charDigitOf(this, radix)
    if (digit < 0) {
        throw IllegalArgumentException("code point ${this.code} is not a valid digit in radix $radix")
    }
    return digit
}

public fun Char.digitToIntOrNull(): Int? = digitToIntOrNull(10)

public fun Char.digitToIntOrNull(radix: Int): Int? {
    val digit = charDigitOf(this, radix)
    return if (digit < 0) null else digit
}

public fun Int.digitToChar(): Char = digitToChar(10)

public fun Int.digitToChar(radix: Int): Char {
    charCheckRadix(radix)
    if (this < 0 || this >= radix) {
        throw IllegalArgumentException("digit $this is out of the valid range 0..<$radix")
    }
    return if (this < 10) {
        __charFromCode(CHAR_CODE_ZERO + this)
    } else {
        __charFromCode(CHAR_CODE_UPPER_A + this - 10)
    }
}

private fun charCheckRadix(radix: Int) {
    if (radix < 2 || radix > 36) {
        throw IllegalArgumentException("radix $radix is out of the valid range 2..36")
    }
}

/// Returns the digit value after applying the radix bound, or -1 when invalid.
private fun charDigitOf(char: Char, radix: Int): Int {
    charCheckRadix(radix)
    val digit = __charDigitValue(char.code)
    return if (digit < 0 || digit >= radix) -1 else digit
}
