package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-662: Char 変換系は純 Kotlin で実装し、Unicode ケースマッピング表と
// ロケール依存変換だけを Swift ランタイムの 1 行ブリッジ (__kk_char_*) に残す。

/// Unicode 完全大文字マッピング（'ß' → "SS" のような多文字マッピングを含む）。
@KsSymbolName("__kk_char_uppercase_string")
internal external fun __charUppercaseString(code: Int): String

/// Unicode 完全小文字マッピング。
@KsSymbolName("__kk_char_lowercase_string")
internal external fun __charLowercaseString(code: Int): String

/// Unicode タイトルケースマッピング。
@KsSymbolName("__kk_char_titlecase_string")
internal external fun __charTitlecaseString(code: Int): String

/// 単一符号位置に収まる大文字マッピング。多文字マッピングや未定義は -1。
@KsSymbolName("__kk_char_uppercase_code")
internal external fun __charUppercaseCode(code: Int): Int

/// 単一符号位置に収まる小文字マッピング。未定義は -1。
@KsSymbolName("__kk_char_lowercase_code")
internal external fun __charLowercaseCode(code: Int): Int

/// 単一符号位置に収まるタイトルケースマッピング。多文字・未定義は -1。
@KsSymbolName("__kk_char_titlecase_code")
internal external fun __charTitlecaseCode(code: Int): Int

/// kotlin.text.digitOf 相当: radix 上限を適用する前の生の桁値。桁でなければ -1。
@KsSymbolName("__kk_char_digit_value")
internal external fun __charDigitValue(code: Int): Int

@KsSymbolName("__kk_char_uppercase_locale")
internal external fun __charUppercaseLocale(code: Int, locale: java.util.Locale): String

@KsSymbolName("__kk_char_lowercase_locale")
internal external fun __charLowercaseLocale(code: Int, locale: java.util.Locale): String

/// 符号位置から Char を作る (既存の Int.toChar() 変換を再利用)。
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

/// radix 上限まで含めた桁値を返す。桁でなければ -1。
private fun charDigitOf(char: Char, radix: Int): Int {
    charCheckRadix(radix)
    val digit = __charDigitValue(char.code)
    return if (digit < 0 || digit >= radix) -1 else digit
}
