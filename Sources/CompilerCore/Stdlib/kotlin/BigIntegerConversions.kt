package kotlin

import java.math.BigInteger

public fun Int.toBigInteger(): BigInteger = BigInteger.valueOf(this.toLong())
