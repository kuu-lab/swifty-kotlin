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

        public fun valueOf(value: Long): BigDecimal = BigDecimal(value.toString())

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

    @KsSymbolName("__kk_bignum_divideMathContext")
    private external fun __kk_bignum_divideMathContext(
        other: BigDecimal,
        precision: Int,
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

    public override fun equals(other: Any?): Boolean {
        if (other !is BigDecimal) return false
        val that = other as BigDecimal
        return scale() == that.scale() && compareTo(that) == 0
    }

    public override fun hashCode(): Int = 31 * unscaledValue().hashCode() + scale()

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

    public fun divide(divisor: BigDecimal, mathContext: MathContext): BigDecimal =
        __kk_bignum_divideMathContext(divisor, mathContext.precision, mathContext.roundingMode.runtimeCode())

    @Deprecated("Use divide(divisor, roundingMode: RoundingMode) instead.")
    public fun divide(divisor: BigDecimal, roundingMode: Int): BigDecimal =
        __kk_bignum_divideAtScale(divisor, scale(), roundingMode)

    @Deprecated("Use divide(divisor, scale, roundingMode: RoundingMode) instead.")
    public fun divide(divisor: BigDecimal, scale: Int, roundingMode: Int): BigDecimal =
        __kk_bignum_divideAtScale(divisor, scale, roundingMode)

    public fun divideToIntegralValue(divisor: BigDecimal): BigDecimal {
        val integral = divide(divisor, 0, RoundingMode.DOWN)
        var resultScale = scale().toLong() - divisor.scale().toLong()
        if (integral.signum() != 0) {
            val digits = integral.unscaledValue().abs().toString()
            var trailingZeros = 0
            var index = digits.length - 1
            while (index >= 0 && digits[index] == '0') {
                trailingZeros++
                index--
            }
            val minimumScale = -trailingZeros.toLong()
            if (resultScale < minimumScale) resultScale = minimumScale
        }
        if (resultScale < Int.MIN_VALUE || resultScale > Int.MAX_VALUE) {
            throw ArithmeticException("BigDecimal scale out of range")
        }
        return integral.setScale(resultScale.toInt(), RoundingMode.UNNECESSARY)
    }

    public fun divideToIntegralValue(divisor: BigDecimal, mathContext: MathContext): BigDecimal {
        val quotient = divideToIntegralValue(divisor)
        val rounded = quotient.round(mathContext)
        if (rounded.compareTo(quotient) != 0) {
            throw ArithmeticException("Division impossible")
        }
        return rounded
    }

    public fun divideAndRemainder(divisor: BigDecimal): Array<BigDecimal> {
        val quotient = divideToIntegralValue(divisor)
        return arrayOf(quotient, subtract(quotient.multiply(divisor)))
    }

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

    public fun precision(): Int = unscaledValue().abs().toString().length

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

    public fun movePointRight(n: Int): BigDecimal {
        val scaled = multiply(BigDecimal("1E" + n))
        return if (scaled.scale() < 0) scaled.setScale(0) else scaled
    }

    public fun movePointLeft(n: Int): BigDecimal = movePointRight(-n)

    public fun signum(): Int = compareTo(ZERO)

    public fun negate(): BigDecimal = multiply(BigDecimal("-1"))

    public fun abs(): BigDecimal = if (signum() < 0) negate() else this

    public fun toPlainString(): String {
        val sign = signum()
        val valueScale = scale()
        if (sign == 0) {
            return if (valueScale > 0) "0." + "0".repeat(valueScale) else "0"
        }
        val digits = unscaledValue().abs().toString()
        val body: String
        if (valueScale == 0) {
            body = digits
        } else if (valueScale > 0) {
            if (digits.length > valueScale) {
                val point = digits.length - valueScale
                body = digits.substring(0, point) + "." + digits.substring(point)
            } else {
                body = "0." + "0".repeat(valueScale - digits.length) + digits
            }
        } else {
            val zeroCount = -valueScale.toLong()
            if (zeroCount > Int.MAX_VALUE.toLong()) {
                throw ArithmeticException("BigDecimal scale out of range")
            }
            body = digits + "0".repeat(zeroCount.toInt())
        }
        return if (sign < 0) "-" + body else body
    }


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
            val exponentText = if (newExponent >= 0) "+" + newExponent else newExponent.toString()
            return mantissa + "E" + exponentText
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

    public fun unscaledValue(): BigInteger = BigInteger(movePointRight(scale()).toString())

    public fun toBigInteger(): BigInteger =
        BigInteger(setScale(0, RoundingMode.DOWN).toString())

    public fun toBigIntegerExact(): BigInteger =
        BigInteger(setScale(0, RoundingMode.UNNECESSARY).toString())

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

    public fun abs(mathContext: MathContext): BigDecimal = abs().round(mathContext)

    public fun negate(mathContext: MathContext): BigDecimal = negate().round(mathContext)

    public fun plus(): BigDecimal = this

    public fun plus(mathContext: MathContext): BigDecimal = round(mathContext)

    public fun min(other: BigDecimal): BigDecimal =
        if (compareTo(other) <= 0) this else other

    public fun max(other: BigDecimal): BigDecimal =
        if (compareTo(other) >= 0) this else other

    public fun ulp(): BigDecimal = BigDecimal("1E" + (-scale().toLong()))

    public fun byteValueExact(): Byte = toBigIntegerExact().byteValueExact()

    public fun shortValueExact(): Short = toBigIntegerExact().shortValueExact()

    public fun intValueExact(): Int = toBigIntegerExact().intValueExact()

    public fun longValueExact(): Long = toBigIntegerExact().longValueExact()

    public operator fun plus(other: BigDecimal): BigDecimal = add(other)

    public operator fun minus(other: BigDecimal): BigDecimal = subtract(other)

    public operator fun times(other: BigDecimal): BigDecimal = multiply(other)

    public operator fun div(other: BigDecimal): BigDecimal =
        divide(other, RoundingMode.HALF_EVEN)

    public operator fun rem(other: BigDecimal): BigDecimal = remainder(other)

    public operator fun unaryMinus(): BigDecimal = negate()

    public operator fun inc(): BigDecimal = add(ONE)

    public operator fun dec(): BigDecimal = subtract(ONE)

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
