package java.math

import kotlin.text.toBigDecimal
import kotlin.internal.KsSymbolName

public class BigDecimal : Number(), Comparable<BigDecimal> {
    public companion object {
        public val ZERO: BigDecimal = "0".toBigDecimal()
        public val ONE: BigDecimal = "1".toBigDecimal()
        public val TEN: BigDecimal = "10".toBigDecimal()

        /**
         * Returns a `BigDecimal` whose value is equal to that of the [value]
         * argument. Unlike the `BigDecimal(Double)` constructor, which keeps
         * the exact binary value, `valueOf` goes through the canonical string
         * representation provided by `Double.toString`, matching the JDK
         * (`valueOf(2.0)` therefore has scale 1).
         */
        public fun valueOf(value: Double): BigDecimal {
            if (!value.isFinite()) throw NumberFormatException("Infinite or NaN")
            return BigDecimal(value.toString())
        }

        /** Returns a `BigDecimal` equal to [value] with scale 0. */
        public fun valueOf(value: Long): BigDecimal = BigDecimal(value.toString())

        /** Returns a `BigDecimal` whose value is `unscaledVal * 10^-scale`. */
        public fun valueOf(unscaledVal: Long, scale: Int): BigDecimal =
            BigDecimal(unscaledVal.toString() + "E" + (-scale.toLong()))
    }

    @KsSymbolName("__kk_string_toBigDecimal")
    public constructor(value: String)

    @KsSymbolName("__kk_double_toBigDecimal")
    public constructor(value: Double)

    @KsSymbolName("__kk_int_toBigDecimal")
    public constructor(value: Int)

    @KsSymbolName("__kk_long_toBigDecimal")
    public constructor(value: Long)

    @KsSymbolName("__kk_bignum_add")
    private external fun __kk_bignum_add(other: BigDecimal): BigDecimal

    @KsSymbolName("__kk_bignum_subtract")
    private external fun __kk_bignum_subtract(other: BigDecimal): BigDecimal

    @KsSymbolName("__kk_bignum_multiply")
    private external fun __kk_bignum_multiply(other: BigDecimal): BigDecimal

    @KsSymbolName("__kk_bignum_divide")
    private external fun __kk_bignum_divide(other: BigDecimal): BigDecimal

    @KsSymbolName("__kk_bignum_divideAtScale")
    private external fun __kk_bignum_divideAtScale(
        other: BigDecimal,
        scale: Int,
        roundingMode: Int
    ): BigDecimal

    @KsSymbolName("__kk_bignum_setScale")
    private external fun __kk_bignum_setScale(scale: Int, roundingMode: Int): BigDecimal

    @KsSymbolName("__kk_bignum_scale")
    private external fun __kk_bignum_scale(): Int

    @KsSymbolName("__kk_bignum_toString")
    private external fun __kk_bignum_toString(): String

    @KsSymbolName("__kk_bignum_compareTo")
    private external fun __kk_bignum_compareTo(other: BigDecimal): Int

    @KsSymbolName("__kk_bignum_toDouble")
    private external fun __kk_bignum_toDouble(): Double

    @KsSymbolName("__kk_bignum_toFloat")
    private external fun __kk_bignum_toFloat(): Float

    @KsSymbolName("__kk_bignum_toLong")
    private external fun __kk_bignum_toLong(): Long

    @KsSymbolName("__kk_bignum_toInt")
    private external fun __kk_bignum_toInt(): Int

    @KsSymbolName("__kk_bignum_toShort")
    private external fun __kk_bignum_toShort(): Short

    @KsSymbolName("__kk_bignum_toByte")
    private external fun __kk_bignum_toByte(): Byte

    override fun toString(): String {
        return __kk_bignum_toString()
    }

    override fun compareTo(other: BigDecimal): Int {
        return __kk_bignum_compareTo(other)
    }

    /** Returns the string representation without an exponent, like the JDK `toPlainString`. */
    public fun toPlainString(): String {
        val scale = scale()
        if (unscaledValue().signum() == 0) {
            return if (scale > 0) "0." + "0".repeat(scale) else "0"
        }
        val digits = unscaledValue().abs().toString()
        val body = if (scale >= 0) {
            val intLength = digits.length - scale
            if (intLength > 0) {
                val intPart = digits.substring(0, intLength)
                val fracPart = digits.substring(intLength)
                if (fracPart.isEmpty()) intPart else intPart + "." + fracPart
            } else {
                "0." + "0".repeat(-intLength) + digits
            }
        } else {
            digits + "0".repeat(-scale)
        }
        return if (signum() < 0) "-" + body else body
    }

    /** Returns the string representation using an exponent divisible by 3, like the JDK. */
    public fun toEngineeringString(): String {
        val plain = toString()
        val marker = plain.indexOf('E')
        if (marker < 0) return plain
        val exponent = plain.substring(marker + 1).toInt()
        if (signum() == 0) {
            val shift = ((3 - (exponent % 3)) % 3 + 3) % 3
            if (shift == 0) return plain
            val newExponent = exponent + shift
            val mantissa = "0" + (if (shift > 0) "." + "0".repeat(shift) else "")
            return mantissa + "E+" + newExponent
        }
        val shift = ((exponent % 3) + 3) % 3
        if (shift == 0) return plain
        val negative = plain[0] == '-'
        val body = if (negative) plain.substring(1, marker) else plain.substring(0, marker)
        val dot = body.indexOf('.')
        val intPart = if (dot < 0) body else body.substring(0, dot)
        val fracPart = if (dot < 0) "" else body.substring(dot + 1)
        var digits = intPart + fracPart
        val newIntLength = intPart.length + shift
        if (digits.length < newIntLength) {
            digits += "0".repeat(newIntLength - digits.length)
        }
        val newInt = digits.substring(0, newIntLength)
        val newFrac = digits.substring(newIntLength)
        val mantissa = if (newFrac.isEmpty()) newInt else newInt + "." + newFrac
        val newExponent = exponent - shift
        if (newExponent == 0) {
            return (if (negative) "-" else "") + mantissa
        }
        val exponentText = if (newExponent >= 0) "+" + newExponent else newExponent.toString()
        return (if (negative) "-" else "") + mantissa + "E" + exponentText
    }

    public fun add(augend: BigDecimal): BigDecimal = __kk_bignum_add(augend)

    public fun add(augend: BigDecimal, mathContext: MathContext): BigDecimal =
        add(augend).round(mathContext)

    public fun subtract(subtrahend: BigDecimal): BigDecimal = __kk_bignum_subtract(subtrahend)

    public fun subtract(subtrahend: BigDecimal, mathContext: MathContext): BigDecimal =
        subtract(subtrahend).round(mathContext)

    public fun multiply(multiplicand: BigDecimal): BigDecimal = __kk_bignum_multiply(multiplicand)

    public fun multiply(multiplicand: BigDecimal, mathContext: MathContext): BigDecimal =
        multiply(multiplicand).round(mathContext)

    public fun divide(divisor: BigDecimal): BigDecimal = __kk_bignum_divide(divisor)

    public fun divide(divisor: BigDecimal, roundingMode: RoundingMode): BigDecimal =
        divide(divisor, scale(), roundingMode)

    public fun divide(
        divisor: BigDecimal,
        scale: Int,
        roundingMode: RoundingMode
    ): BigDecimal = __kk_bignum_divideAtScale(divisor, scale, roundingMode.runtimeCode())

    /** Returns the quotient rounded to the precision and rounding mode of [mathContext]. */
    public fun divide(divisor: BigDecimal, mathContext: MathContext): BigDecimal {
        if (mathContext.precision == 0) return divide(divisor)
        val exact = try {
            divide(divisor)
        } catch (e: ArithmeticException) {
            return this.divideRoundedByMathContext(divisor, mathContext)
        }
        return exact.round(mathContext)
    }

    @Deprecated("Use divide(divisor, roundingMode: RoundingMode) instead.")
    public fun divide(divisor: BigDecimal, roundingMode: Int): BigDecimal =
        __kk_bignum_divideAtScale(divisor, scale(), roundingMode)

    @Deprecated("Use divide(divisor, scale, roundingMode: RoundingMode) instead.")
    public fun divide(divisor: BigDecimal, scale: Int, roundingMode: Int): BigDecimal =
        __kk_bignum_divideAtScale(divisor, scale, roundingMode)

    /**
     * Returns the integer part of the quotient rounded toward zero, with the
     * JDK preferred scale `this.scale() - divisor.scale()` when it can be
     * represented exactly.
     */
    public fun divideToIntegralValue(divisor: BigDecimal): BigDecimal {
        val quotient = divide(divisor, 0, RoundingMode.DOWN)
        val preferredScaleLong = scale().toLong() - divisor.scale().toLong()
        if (preferredScaleLong < Int.MIN_VALUE || preferredScaleLong > Int.MAX_VALUE) {
            throw ArithmeticException("BigDecimal scale out of range")
        }
        val preferredScale = preferredScaleLong.toInt()
        if (quotient.signum() == 0) {
            return BigDecimal("0E" + (-preferredScale.toLong()))
        }
        if (preferredScale >= 0) {
            return quotient.setScale(preferredScale)
        }
        val stripped = quotient.stripTrailingZeros()
        return if (stripped.scale() <= preferredScale) {
            stripped.setScale(preferredScale, RoundingMode.UNNECESSARY)
        } else {
            stripped
        }
    }

    public fun divideToIntegralValue(divisor: BigDecimal, mathContext: MathContext): BigDecimal =
        divideToIntegralValue(divisor).round(mathContext)

    /** Returns `(quotient, remainder)` for division by [divisor], like the JDK. */
    public fun divideAndRemainder(divisor: BigDecimal): Array<BigDecimal> {
        val quotient = divideToIntegralValue(divisor)
        return arrayOf(quotient, subtract(quotient.multiply(divisor)))
    }

    /**
     * Returns a `BigDecimal` whose value is `(this % divisor)`. Like the JDK,
     * the result is `this - divideToIntegralValue(divisor) * divisor`, so its
     * sign follows this value.
     */
    public fun remainder(divisor: BigDecimal): BigDecimal =
        subtract(divideToIntegralValue(divisor).multiply(divisor))

    public fun setScale(newScale: Int): BigDecimal =
        __kk_bignum_setScale(newScale, RoundingMode.UNNECESSARY.runtimeCode())

    public fun setScale(newScale: Int, roundingMode: RoundingMode): BigDecimal =
        __kk_bignum_setScale(newScale, roundingMode.runtimeCode())

    @Deprecated("Use setScale(newScale, roundingMode: RoundingMode) instead.")
    public fun setScale(newScale: Int, roundingMode: Int): BigDecimal =
        __kk_bignum_setScale(newScale, roundingMode)

    public fun scale(): Int = __kk_bignum_scale()

    /** Returns the number of digits in the unscaled value of this `BigDecimal`. */
    public fun precision(): Int = unscaledValue().abs().toString().length

    /**
     * Returns a `BigDecimal` whose value is `(this^n)`, computed exactly.
     * Like the JDK, the exponent must satisfy `0 <= n <= 999999999`; the
     * preferred scale of the result is `this.scale() * n`. Repeated
     * squaring keeps the number of exact decimal multiplications logarithmic
     * in `n` while producing the identical unscaled value and scale.
     */
    public fun pow(n: Int): BigDecimal {
        if (n < 0 || n > 999999999) throw ArithmeticException("Invalid operation")
        if (n == 0) return ONE
        var result = ONE
        var base = this
        var remaining = n
        while (remaining > 0) {
            if ((remaining and 1) != 0) result = result.multiply(base)
            remaining = remaining shr 1
            if (remaining > 0) base = base.multiply(base)
        }
        return result
    }

    /**
     * Returns a `BigDecimal` whose scale is reduced by [n] (value multiplied by 10^n).
     * Like the JDK, when the resulting scale would go below zero the unscaled
     * value is padded instead, so the result's scale is never negative.
     */
    public fun movePointRight(n: Int): BigDecimal {
        val scaled = multiply(BigDecimal("1E" + n))
        return if (scaled.scale() < 0) scaled.setScale(0) else scaled
    }

    /**
     * Returns a `BigDecimal` whose scale is increased by [n] (value multiplied by 10^-n)
     * while the unscaled value is preserved. A negative [n] shifts the point right.
     */
    public fun movePointLeft(n: Int): BigDecimal = movePointRight(-n)

    /** Returns -1, 0, or 1 as this value is negative, zero, or positive. */
    public fun signum(): Int = compareTo(ZERO)

    /** The unscaled integer value carried by this `BigDecimal`. */
    public fun unscaledValue(): BigInteger = BigInteger(movePointRight(scale()).toString())

    /** This value converted to a `BigInteger`, dropping any fractional part toward zero. */
    public fun toBigInteger(): BigInteger =
        BigInteger(setScale(0, RoundingMode.DOWN).toString())

    /**
     * This value converted to a `BigInteger`; throws `ArithmeticException`
     * if a nonzero fractional part would be dropped.
     */
    public fun toBigIntegerExact(): BigInteger =
        BigInteger(setScale(0, RoundingMode.UNNECESSARY).toString())

    /**
     * Returns a `BigDecimal` which is numerically equal to this value but with
     * any trailing zeros removed from the unscaled value. Like the JDK, the
     * scale may become negative (e.g. `BigDecimal("1000")` becomes `1E+3`), and
     * zero returns `BigDecimal.ZERO`.
     */
    public fun stripTrailingZeros(): BigDecimal {
        val unscaled = unscaledValue()
        if (unscaled.signum() == 0) return ZERO
        var stripped = unscaled
        var newScale = scale()
        while (stripped.remainder(BigInteger.TEN).signum() == 0) {
            stripped = stripped.divide(BigInteger.TEN)
            newScale--
        }
        if (newScale == scale()) return this
        return BigDecimal(stripped.toString() + "E" + (-newScale.toLong()))
    }

    /** Returns this value rounded to the precision and rounding mode of [mathContext]. */
    public fun round(mathContext: MathContext): BigDecimal {
        val precision = mathContext.precision
        if (precision == 0) return this
        val excessDigits = this.significantDigitCount() - precision
        if (excessDigits <= 0) return this
        val targetScale = scale().toLong() - excessDigits.toLong()
        if (targetScale < Int.MIN_VALUE || targetScale > Int.MAX_VALUE) {
            throw ArithmeticException("BigDecimal scale out of range")
        }
        var rounded = setScale(targetScale.toInt(), mathContext.roundingMode)
        while (rounded.significantDigitCount() > precision) {
            val reducedScale = rounded.scale().toLong() - 1
            if (reducedScale < Int.MIN_VALUE) {
                throw ArithmeticException("BigDecimal scale out of range")
            }
            rounded = rounded.setScale(reducedScale.toInt(), RoundingMode.UNNECESSARY)
        }
        return rounded
    }

    public fun abs(): BigDecimal = if (signum() < 0) ZERO.subtract(this) else this

    public fun abs(mathContext: MathContext): BigDecimal = abs().round(mathContext)

    public fun negate(): BigDecimal = ZERO.subtract(this)

    public fun negate(mathContext: MathContext): BigDecimal = negate().round(mathContext)

    public fun plus(): BigDecimal = this

    public fun plus(mathContext: MathContext): BigDecimal = round(mathContext)

    public fun min(other: BigDecimal): BigDecimal =
        if (compareTo(other) <= 0) this else other

    public fun max(other: BigDecimal): BigDecimal =
        if (compareTo(other) >= 0) this else other

    /** Returns one unit in the last place of this value, like the JDK `ulp`. */
    public fun ulp(): BigDecimal =
        if (signum() == 0) ONE else BigDecimal("1E" + (-scale().toLong()))

    public fun byteValueExact(): Byte = toBigIntegerExact().byteValueExact()

    public fun shortValueExact(): Short = toBigIntegerExact().shortValueExact()

    public fun intValueExact(): Int = toBigIntegerExact().intValueExact()

    public fun longValueExact(): Long = toBigIntegerExact().longValueExact()

    public operator fun plus(other: BigDecimal): BigDecimal = add(other)

    public operator fun minus(other: BigDecimal): BigDecimal = subtract(other)

    public operator fun times(other: BigDecimal): BigDecimal = multiply(other)

    public operator fun div(other: BigDecimal): BigDecimal = divide(other)

    public override fun toDouble(): Double = __kk_bignum_toDouble()

    public override fun toFloat(): Float = __kk_bignum_toFloat()

    public override fun toLong(): Long = __kk_bignum_toLong()

    public override fun toInt(): Int = __kk_bignum_toInt()

    public override fun toShort(): Short = __kk_bignum_toShort()

    public override fun toByte(): Byte = __kk_bignum_toByte()
}

private fun BigDecimal.significantDigitCount(): Int {
    val mantissa = toString().substringBefore("E").removePrefix("-")
    val digits = mantissa.replace(".", "").trimStart('0')
    return if (digits.isEmpty()) 1 else digits.length
}

private fun BigDecimal.divideRoundedByMathContext(
    divisor: BigDecimal,
    mathContext: MathContext
): BigDecimal {
    val precision = mathContext.precision
    val exponent = decimalExponentOfQuotient(divisor)
    val targetScale = precision.toLong() - 1L - exponent.toLong()
    if (targetScale < Int.MIN_VALUE || targetScale > Int.MAX_VALUE) {
        throw ArithmeticException("BigDecimal scale out of range")
    }
    return divide(divisor, targetScale.toInt(), mathContext.roundingMode).round(mathContext)
}

private fun BigDecimal.decimalExponentOfQuotient(divisor: BigDecimal): Int {
    if (signum() == 0 || divisor.signum() == 0) return 0
    val lhs = unscaledValue().abs().toString()
    val rhs = divisor.unscaledValue().abs().toString()
    var power = lhs.length - rhs.length
    val comparison = if (power >= 0) {
        comparePaddedDecimalStrings(lhs, 0, rhs, power)
    } else {
        comparePaddedDecimalStrings(lhs, -power, rhs, 0)
    }
    if (comparison < 0) power -= 1
    val exponent = power.toLong() + divisor.scale().toLong() - scale().toLong()
    if (exponent < Int.MIN_VALUE || exponent > Int.MAX_VALUE) {
        throw ArithmeticException("BigDecimal scale out of range")
    }
    return exponent.toInt()
}

private fun comparePaddedDecimalStrings(
    lhs: String,
    lhsZeros: Int,
    rhs: String,
    rhsZeros: Int
): Int {
    val lhsLength = lhs.length.toLong() + lhsZeros.toLong()
    val rhsLength = rhs.length.toLong() + rhsZeros.toLong()
    if (lhsLength != rhsLength) return if (lhsLength < rhsLength) -1 else 1
    var index = 0L
    while (index < lhsLength) {
        val intIndex = index.toInt()
        val lhsDigit = if (intIndex < lhs.length) lhs[intIndex] else '0'
        val rhsDigit = if (intIndex < rhs.length) rhs[intIndex] else '0'
        if (lhsDigit != rhsDigit) return if (lhsDigit < rhsDigit) -1 else 1
        index++
    }
    return 0
}

private fun RoundingMode.runtimeCode(): Int = when (this) {
    RoundingMode.UP -> 0
    RoundingMode.DOWN -> 1
    RoundingMode.CEILING -> 2
    RoundingMode.FLOOR -> 3
    RoundingMode.HALF_UP -> 4
    RoundingMode.HALF_DOWN -> 5
    RoundingMode.HALF_EVEN -> 6
    RoundingMode.UNNECESSARY -> 7
}
