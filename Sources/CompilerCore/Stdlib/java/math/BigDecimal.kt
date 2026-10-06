package java.math

import kotlin.internal.KsSymbolName

public class BigDecimal : Comparable<BigDecimal> {
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
