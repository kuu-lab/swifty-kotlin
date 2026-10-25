package kotlin

import java.math.BigDecimal
import java.math.BigInteger
import java.math.MathContext
import java.math.RoundingMode
import kotlin.text.toBigDecimal

public fun String.toBigInteger(): BigInteger = BigInteger(this)

public fun String.toBigInteger(radix: Int): BigInteger = BigInteger(this, radix)

public fun String.toBigIntegerOrNull(): BigInteger? =
    try {
        BigInteger(this)
    } catch (_: NumberFormatException) {
        null
    }

public fun String.toBigIntegerOrNull(radix: Int): BigInteger? =
    try {
        BigInteger(this, radix)
    } catch (_: NumberFormatException) {
        null
    }

public fun Long.toBigInteger(): BigInteger = BigInteger.valueOf(this)

public fun Int.toBigDecimal(): BigDecimal = this.toString().toBigDecimal()

public fun Long.toBigDecimal(): BigDecimal = this.toString().toBigDecimal()

public fun Double.toBigDecimal(): BigDecimal = this.toString().toBigDecimal()

public fun Int.toBigDecimal(mathContext: MathContext): BigDecimal =
    this.toString().toBigDecimal().roundToMathContext(mathContext)

public fun Long.toBigDecimal(mathContext: MathContext): BigDecimal =
    this.toString().toBigDecimal().roundToMathContext(mathContext)

public fun Double.toBigDecimal(mathContext: MathContext): BigDecimal =
    this.toString().toBigDecimal().roundToMathContext(mathContext)

public fun BigInteger.toBigDecimal(): BigDecimal = toString().toBigDecimal()

private fun BigDecimal.roundToMathContext(mathContext: MathContext): BigDecimal {
    val precision = mathContext.precision
    if (precision == 0) return this

    val excessDigits = significantDigitCount() - precision
    if (excessDigits <= 0) return this

    val targetScale = scale().toLong() - excessDigits.toLong()
    if (targetScale < Int.MIN_VALUE || targetScale > Int.MAX_VALUE) {
        throw ArithmeticException("BigDecimal scale out of range")
    }

    var rounded = setScale(targetScale.toInt(), mathContext.roundingMode)
    // Rounding can carry into one additional digit (for example, 999 at
    // precision 2). Remove only exact trailing zeroes to keep the requested
    // precision without changing the represented value.
    while (rounded.significantDigitCount() > precision) {
        val reducedScale = rounded.scale().toLong() - 1
        if (reducedScale < Int.MIN_VALUE) {
            throw ArithmeticException("BigDecimal scale out of range")
        }
        rounded = rounded.setScale(reducedScale.toInt(), RoundingMode.UNNECESSARY)
    }
    return rounded
}

private fun BigDecimal.significantDigitCount(): Int {
    val mantissa = toString().substringBefore("E").removePrefix("-")
    val digits = mantissa.replace(".", "").trimStart('0')
    return if (digits.isEmpty()) 1 else digits.length
}
