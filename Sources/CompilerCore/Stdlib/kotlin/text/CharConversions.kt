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

/// Simple (one-to-one) uppercase mapping; returns -1 for surrogate code units.
@KsSymbolName("__kk_char_uppercase_code")
internal external fun __charUppercaseCode(code: Int): Int

/// Simple (one-to-one) lowercase mapping; returns -1 for surrogate code units.
@KsSymbolName("__kk_char_lowercase_code")
internal external fun __charLowercaseCode(code: Int): Int

/// One-to-one titlecase mapping; returns -1 for multi-scalar or undefined mappings.
@KsSymbolName("__kk_char_titlecase_code")
internal external fun __charTitlecaseCode(code: Int): Int

/// Equivalent to kotlin.text.digitOf before applying the radix bound; returns -1 for non-digits.
@KsSymbolName("__kk_char_digit_value")
internal external fun __charDigitValue(code: Int): Int

/// Java Character.getNumericValue semantics for Unicode numeric symbols.
@KsSymbolName("__kk_char_numeric_value")
internal external fun __charNumericValue(code: Int): Int

@KsSymbolName("__kk_char_uppercase_locale")
internal external fun __charUppercaseLocale(code: Int, locale: java.util.Locale): String

@KsSymbolName("__kk_char_lowercase_locale")
internal external fun __charLowercaseLocale(code: Int, locale: java.util.Locale): String

/// Builds a Char from a code point by reusing the existing Int.toChar() conversion.
@KsSymbolName("kk_int_to_char")
@PublishedApi
internal external fun __charFromCode(code: Int): Char

private const val CHAR_CODE_ZERO = 48 // '0'
private const val CHAR_CODE_UPPER_A = 65 // 'A'

public fun Char.uppercase(): String = __charUppercaseString(this.code)

public fun Char.lowercase(): String = __charLowercaseString(this.code)

public fun Char.titlecase(): String = __charTitlecaseString(this.code)

public fun Char.uppercase(locale: java.util.Locale): String = __charUppercaseLocale(this.code, locale)

public fun Char.lowercase(locale: java.util.Locale): String = __charLowercaseLocale(this.code, locale)

/**
 * This function supports one-to-many character mapping, thus the length of the returned
 * string can be greater than one. If this character has no title case mapping, the result
 * of `uppercase(locale)` is returned instead.
 */
@SinceKotlin("1.5")
public fun Char.titlecase(locale: java.util.Locale): String {
    val localizedUppercase = uppercase(locale)
    if (localizedUppercase.length > 1) {
        return if (this == 'ŉ') {
            localizedUppercase
        } else {
            localizedUppercase.substring(0, 1) + localizedUppercase.substring(1).lowercase()
        }
    }
    if (localizedUppercase != uppercase()) {
        return localizedUppercase
    }
    return titlecaseChar().toString()
}

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

/** Deprecated by Kotlin, but still provided for compatibility. */
@Deprecated("Use lowercaseChar() instead.", ReplaceWith("lowercaseChar()"))
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.1")
public fun Char.toLowerCase(): Char = lowercaseChar()

/** Deprecated by Kotlin, but still provided for compatibility. */
@Deprecated("Use uppercaseChar() instead.", ReplaceWith("uppercaseChar()"))
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.1")
public fun Char.toUpperCase(): Char = uppercaseChar()

/** Deprecated by Kotlin, but still provided for compatibility. */
@Deprecated("Use titlecaseChar() instead.", ReplaceWith("titlecaseChar()"))
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.1")
public fun Char.toTitleCase(): Char = titlecaseChar()

public operator fun Char.inc(): Char = __charFromCode(this.code + 1)

public operator fun Char.dec(): Char = __charFromCode(this.code - 1)

public fun Char.digitToInt(): Int =
    digitToIntOrNull(10) ?: throw IllegalArgumentException("Char $this is not a decimal digit")

public fun Char.digitToInt(radix: Int): Int =
    digitToIntOrNull(radix) ?: throw IllegalArgumentException("Char $this is not a digit in the given radix=$radix")

public fun Char.digitToIntOrNull(): Int? = digitToIntOrNull(10)

public fun Char.digitToIntOrNull(radix: Int): Int? {
    val digit = charDigitOf(this, radix)
    return if (digit < 0) null else digit
}

public fun Int.digitToChar(): Char {
    if (this < 0 || this > 9) {
        throw IllegalArgumentException("Int $this is not a decimal digit")
    }
    return __charFromCode(CHAR_CODE_ZERO + this)
}

public fun Int.digitToChar(radix: Int): Char {
    if (radix < 2 || radix > 36) {
        throw IllegalArgumentException("Invalid radix: $radix. Valid radix values are in range 2..36")
    }
    if (this < 0 || this >= radix) {
        throw IllegalArgumentException("Digit $this does not represent a valid digit in radix $radix")
    }
    return if (this < 10) {
        __charFromCode(CHAR_CODE_ZERO + this)
    } else {
        __charFromCode(CHAR_CODE_UPPER_A + this - 10)
    }
}

private fun charCheckRadix(radix: Int) {
    if (radix < 2 || radix > 36) {
        throw IllegalArgumentException("radix $radix was not in valid range 2..36")
    }
}

private fun charDigitOf(char: Char, radix: Int): Int {
    charCheckRadix(radix)
    val digit = __charDigitValue(char.code)
    return if (digit < 0 || digit >= radix) -1 else digit
}
