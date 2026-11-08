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

    public fun add(augend: BigDecimal): BigDecimal = __kk_bignum_add(augend)

    public fun subtract(subtrahend: BigDecimal): BigDecimal = __kk_bignum_subtract(subtrahend)

    public fun multiply(multiplicand: BigDecimal): BigDecimal = __kk_bignum_multiply(multiplicand)

    public fun divide(divisor: BigDecimal): BigDecimal = __kk_bignum_divide(divisor)

    public fun divide(divisor: BigDecimal, roundingMode: RoundingMode): BigDecimal =
        divide(divisor, scale(), roundingMode)

    public fun divide(
        divisor: BigDecimal,
        scale: Int,
        roundingMode: RoundingMode
    ): BigDecimal = __kk_bignum_divideAtScale(divisor, scale, roundingMode.runtimeCode())

    @Deprecated("Use divide(divisor, roundingMode: RoundingMode) instead.")
    public fun divide(divisor: BigDecimal, roundingMode: Int): BigDecimal =
        __kk_bignum_divideAtScale(divisor, scale(), roundingMode)

    @Deprecated("Use divide(divisor, scale, roundingMode: RoundingMode) instead.")
    public fun divide(divisor: BigDecimal, scale: Int, roundingMode: Int): BigDecimal =
        __kk_bignum_divideAtScale(divisor, scale, roundingMode)

    /**
     * Returns a `BigDecimal` whose value is `(this % divisor)`. Like the JDK,
     * the result is `this - divideToIntegralValue(divisor) * divisor`, so its
     * sign follows this value and its scale is `max(this.scale(),
     * divisor.scale())` adjusted by the subtraction.
     */
    public fun remainder(divisor: BigDecimal): BigDecimal =
        subtract(divide(divisor, 0, RoundingMode.DOWN).multiply(divisor))

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
