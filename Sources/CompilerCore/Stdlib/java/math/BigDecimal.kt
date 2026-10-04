package java.math

import kotlin.internal.KsSymbolName

public class BigDecimal {
    @KsSymbolName("__kk_bignum_toString")
    private external fun __kk_bignum_toString(): String

    override fun toString(): String {
        return __kk_bignum_toString()
    }
}
