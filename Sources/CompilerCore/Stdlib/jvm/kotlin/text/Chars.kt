package kotlin.text

import kotlin.jvm.internal.__jvmUpperChar
import kotlin.jvm.internal.__jvmLowerChar
import kotlin.jvm.internal.__jvmTitleChar
import kotlin.jvm.internal.__jvmWhitespace
import kotlin.jvm.internal.__jvmSpaceChar
import kotlin.jvm.internal.__jvmIsDigit
import kotlin.jvm.internal.__jvmIsLetter
import kotlin.jvm.internal.__jvmCharDigit
import kotlin.jvm.internal.__jvmDirectionality
import kotlin.jvm.internal.__jvmIsLowerCase
import kotlin.jvm.internal.__jvmIsUpperCase

@kotlin.internal.InlineOnly
public inline operator fun Char.inc(): Char = (this.code + 1).toChar()

@kotlin.internal.InlineOnly
public inline operator fun Char.dec(): Char = (this.code - 1).toChar()

public fun Char.isHighSurrogate(): Boolean = this >= '\uD800' && this <= '\uDBFF'

public fun Char.isLowSurrogate(): Boolean = this >= '\uDC00' && this <= '\uDFFF'

public fun Char.isDigit(): Boolean = __jvmIsDigit(this)

public fun Char.isLetter(): Boolean = __jvmIsLetter(this)

public fun Char.isLetterOrDigit(): Boolean = isLetter() || isDigit()

public fun Char.isLowerCase(): Boolean = __jvmIsLowerCase(this)

public fun Char.isUpperCase(): Boolean = __jvmIsUpperCase(this)

public fun Char.uppercaseChar(): Char = __jvmUpperChar(this)

public fun Char.lowercaseChar(): Char = __jvmLowerChar(this)

public fun Char.uppercase(): String = this.toString().uppercase()

public fun Char.lowercase(): String = this.toString().lowercase()

public fun Char.titlecase(): String {
    val uppercase = this.toString().uppercase()
    if (uppercase.length > 1) {
        return if (this == 'ŉ') {
            uppercase
        } else {
            uppercase.substring(0, 1) + uppercase.substring(1).lowercase()
        }
    }
    return __jvmTitleChar(this).toString()
}

public fun Char.isWhitespace(): Boolean = __jvmWhitespace(this) || __jvmSpaceChar(this)

public fun Char.digitToIntOrNull(): Int? = digitToIntOrNull(10)

public fun Char.digitToIntOrNull(radix: Int): Int? {
    checkRadix(radix)
    val digit = __jvmCharDigit(this, radix)
    return if (digit < 0) null else digit
}

public val Char.directionality: CharDirectionality
    get() {
        val directionality = __jvmDirectionality(this)
        return when (directionality) {
            -1 -> CharDirectionality.UNDEFINED
            0 -> CharDirectionality.LEFT_TO_RIGHT
            1 -> CharDirectionality.RIGHT_TO_LEFT
            2 -> CharDirectionality.RIGHT_TO_LEFT_ARABIC
            3 -> CharDirectionality.EUROPEAN_NUMBER
            4 -> CharDirectionality.EUROPEAN_NUMBER_SEPARATOR
            5 -> CharDirectionality.EUROPEAN_NUMBER_TERMINATOR
            6 -> CharDirectionality.ARABIC_NUMBER
            7 -> CharDirectionality.COMMON_NUMBER_SEPARATOR
            8 -> CharDirectionality.NONSPACING_MARK
            9 -> CharDirectionality.BOUNDARY_NEUTRAL
            10 -> CharDirectionality.PARAGRAPH_SEPARATOR
            11 -> CharDirectionality.SEGMENT_SEPARATOR
            12 -> CharDirectionality.WHITESPACE
            13 -> CharDirectionality.OTHER_NEUTRALS
            14 -> CharDirectionality.LEFT_TO_RIGHT_EMBEDDING
            15 -> CharDirectionality.LEFT_TO_RIGHT_OVERRIDE
            16 -> CharDirectionality.RIGHT_TO_LEFT_EMBEDDING
            17 -> CharDirectionality.RIGHT_TO_LEFT_OVERRIDE
            18 -> CharDirectionality.POP_DIRECTIONAL_FORMAT
            else -> throw IllegalArgumentException("Directionality #$directionality is not defined.")
        }
    }

public fun Char.toFloat(): Float = this.code.toFloat()

public fun Char.equals(other: Char, ignoreCase: Boolean = false): Boolean {
    if (this == other) return true
    if (!ignoreCase) return false
    val thisUpper = this.uppercaseChar()
    val otherUpper = other.uppercaseChar()
    return thisUpper == otherUpper || thisUpper.lowercaseChar() == otherUpper.lowercaseChar()
}

public fun checkRadix(radix: Int): Int {
    if (radix < 2 || radix > 36) throw IllegalArgumentException("radix $radix was not in valid range 2..36")
    return radix
}
