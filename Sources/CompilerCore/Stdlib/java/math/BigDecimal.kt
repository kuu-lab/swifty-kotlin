package java.math

import kotlin.text.toBigDecimal
import kotlin.internal.KsSymbolName

public class BigDecimal : Number(), Comparable<BigDecimal> {
    public companion object {
        public val ZERO: BigDecimal = "0".toBigDecimal()
        public val ONE: BigDecimal = "1".toBigDecimal()
    }

    @KsSymbolName("__kk_string_toBigDecimal")
    public constructor(value: String)

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

    public fun setScale(newScale: Int): BigDecimal =
        __kk_bignum_setScale(newScale, RoundingMode.UNNECESSARY.runtimeCode())

    public fun setScale(newScale: Int, roundingMode: RoundingMode): BigDecimal =
        __kk_bignum_setScale(newScale, roundingMode.runtimeCode())

    @Deprecated("Use setScale(newScale, roundingMode: RoundingMode) instead.")
    public fun setScale(newScale: Int, roundingMode: Int): BigDecimal =
        __kk_bignum_setScale(newScale, roundingMode)

    public fun scale(): Int = __kk_bignum_scale()

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
