package java.math

import kotlin.internal.KsSymbolName

public class BigInteger {
    @KsSymbolName("kk_biginteger_toString")
    private external fun __kk_bignum_toString(): String

    override fun toString(): String {
        return __kk_bignum_toString()
    }
}
