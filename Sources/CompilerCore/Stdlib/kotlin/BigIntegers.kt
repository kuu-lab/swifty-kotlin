package kotlin

import java.math.BigDecimal
import java.math.BigInteger
import kotlin.text.toBigDecimal

public fun String.toBigInteger(): BigInteger = BigInteger(this)

public fun String.toBigInteger(radix: Int): BigInteger = BigInteger(this, radix)

public fun String.toBigIntegerOrNull(): BigInteger? =
    try {
        BigInteger(this)
    } catch (_: NumberFormatException) {
        null
    }

public fun String.toBigIntegerOrNull(radix: Int): BigInteger? =
    try {
        BigInteger(this, radix)
    } catch (_: NumberFormatException) {
        null
    }

public fun Long.toBigInteger(): BigInteger = BigInteger.valueOf(this)

public fun BigInteger.toBigDecimal(): BigDecimal = toString().toBigDecimal()
