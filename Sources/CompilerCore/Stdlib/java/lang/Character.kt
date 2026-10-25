package java.lang

import kotlin.text.__charDigitValue
import kotlin.text.__charFromCode
import kotlin.text.__charIsLowerCase
import kotlin.text.__charIsUpperCase
import kotlin.text.__charLowercaseCode
import kotlin.text.__charNumericValue
import kotlin.text.__charTitlecaseCode
import kotlin.text.__charUnicodeCategory
import kotlin.text.__charUppercaseCode

/** Java-compatible Unicode operations for UTF-16 chars and Unicode code points. */
public object Character {
    public const val NON_SPACING_MARK: Byte = 6
    public const val ENCLOSING_MARK: Byte = 7
    public const val FORMAT: Byte = 16

    private const val UPPERCASE_LETTER: Int = 1
    private const val OTHER_LETTER: Int = 5
    private const val DECIMAL_DIGIT_NUMBER: Int = 9
    private const val SPACE_SEPARATOR: Int = 12
    private const val LINE_SEPARATOR: Int = 13
    private const val PARAGRAPH_SEPARATOR: Int = 14

    // Java deliberately does not validate code points for this operation.
    public fun charCount(codePoint: Int): Int = if (codePoint >= 0x10000) 2 else 1

    public fun isDigit(ch: Char): Boolean = ch.isDigit()

    public fun isDigit(codePoint: Int): Boolean = getType(codePoint) == DECIMAL_DIGIT_NUMBER

    public fun isLetter(ch: Char): Boolean = ch.isLetter()

    public fun isLetter(codePoint: Int): Boolean {
        val type = getType(codePoint)
        return type in UPPERCASE_LETTER..OTHER_LETTER
    }

    public fun isLetterOrDigit(ch: Char): Boolean = isLetter(ch) || isDigit(ch)

    public fun isLetterOrDigit(codePoint: Int): Boolean = isLetter(codePoint) || isDigit(codePoint)

    public fun isUpperCase(ch: Char): Boolean = ch.isUpperCase()

    public fun isUpperCase(codePoint: Int): Boolean = __charIsUpperCase(codePoint)

    public fun isLowerCase(ch: Char): Boolean = ch.isLowerCase()

    public fun isLowerCase(codePoint: Int): Boolean = __charIsLowerCase(codePoint)

    public fun isTitleCase(ch: Char): Boolean = ch.isTitleCase()

    public fun isTitleCase(codePoint: Int): Boolean = getType(codePoint) == 3

    public fun isSpaceChar(codePoint: Int): Boolean {
        val category = getType(codePoint)
        return category in SPACE_SEPARATOR..PARAGRAPH_SEPARATOR
    }

    public fun isSpaceChar(ch: Char): Boolean = isSpaceChar(ch.code)

    public fun isWhitespace(ch: Char): Boolean = isWhitespace(ch.code)

    public fun isWhitespace(codePoint: Int): Boolean {
        return when (getType(codePoint)) {
            SPACE_SEPARATOR -> codePoint != 0x00A0 && codePoint != 0x2007 && codePoint != 0x202F
            LINE_SEPARATOR, PARAGRAPH_SEPARATOR -> true
            else -> codePoint in 0x09..0x0D || codePoint in 0x1C..0x1F
        }
    }

    public fun isISOControl(ch: Char): Boolean = isISOControl(ch.code)

    public fun isISOControl(codePoint: Int): Boolean = codePoint in 0x00..0x1F || codePoint in 0x7F..0x9F

    public fun toUpperCase(ch: Char): Char = ch.uppercaseChar()

    public fun toUpperCase(codePoint: Int): Int = __charUppercaseCode(codePoint).let {
        if (it < 0) codePoint else it
    }

    public fun toLowerCase(ch: Char): Char = ch.lowercaseChar()

    public fun toLowerCase(codePoint: Int): Int = __charLowercaseCode(codePoint).let {
        if (it < 0) codePoint else it
    }

    public fun toTitleCase(ch: Char): Char = ch.titlecaseChar()

    public fun toTitleCase(codePoint: Int): Int = __charTitlecaseCode(codePoint).let {
        if (it < 0) toUpperCase(codePoint) else it
    }

    public fun digit(ch: Char, radix: Int): Int = digit(ch.code, radix)

    public fun digit(codePoint: Int, radix: Int): Int {
        if (radix !in 2..36) return -1
        val value = __charDigitValue(codePoint)
        return if (value in 0 until radix) value else -1
    }

    public fun forDigit(digit: Int, radix: Int): Char {
        if (radix !in 2..36 || digit !in 0 until radix) return __charFromCode(0)
        return if (digit < 10) __charFromCode('0'.code + digit)
        else __charFromCode('a'.code + digit - 10)
    }

    public fun getNumericValue(ch: Char): Int = getNumericValue(ch.code)

    public fun getNumericValue(codePoint: Int): Int {
        val digitValue = digit(codePoint, 36)
        return if (digitValue >= 0) digitValue else __charNumericValue(codePoint)
    }

    public fun getType(codePoint: Int): Int {
        // The shared Unicode bridge returns Kotlin CharCategory ordinals.
        // Java leaves value 17 unused, so PRIVATE_USE and later categories shift by one.
        val ordinal = __charUnicodeCategory(codePoint)
        return if (ordinal >= 17) ordinal + 1 else ordinal
    }
}
