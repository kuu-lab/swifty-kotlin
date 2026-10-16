package java.math

import kotlin.text.toBigDecimal
import kotlin.internal.KsSymbolName

public class BigDecimal : Comparable<BigDecimal> {
    public companion object {
        public val ZERO: BigDecimal = "0".toBigDecimal()
        public val ONE: BigDecimal = "1".toBigDecimal()
    }

    @KsSymbolName("__kk_bignum_toString")
    private external fun __kk_bignum_toString(): String

    @KsSymbolName("__kk_bignum_compareTo")
    private external fun __kk_bignum_compareTo(other: BigDecimal): Int

    override fun toString(): String {
        return __kk_bignum_toString()
    }

    override fun compareTo(other: BigDecimal): Int {
        return __kk_bignum_compareTo(other)
    }
}
