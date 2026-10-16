package java.math

import kotlin.internal.KsSymbolName

public class BigDecimal : Number(), Comparable<BigDecimal> {
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

    public override fun toDouble(): Double = __kk_bignum_toDouble()

    public override fun toFloat(): Float = __kk_bignum_toFloat()

    public override fun toLong(): Long = __kk_bignum_toLong()

    public override fun toInt(): Int = __kk_bignum_toInt()

    public override fun toShort(): Short = __kk_bignum_toShort()

    public override fun toByte(): Byte = __kk_bignum_toByte()
}
