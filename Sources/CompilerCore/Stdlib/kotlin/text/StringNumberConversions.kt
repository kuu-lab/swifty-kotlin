package kotlin.text

// KSP-717: Int/Long.toString(radix) migrated off the kk_int_toString_radix
// runtime bridge. Digits are produced in negative space (n stays <= 0
// throughout) so Int.MIN_VALUE / Long.MIN_VALUE never need to be negated.
//
// Kotlin.digitToChar(radix) uses uppercase 'A'..'Z' for digits >= 10, but
// real Int/Long.toString(radix) uses lowercase 'a'..'z' (verified against
// kotlinc) — the two are independent conventions, so this uses its own
// lowercase digit table rather than digitToChar.

private const val TO_STRING_RADIX_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

private fun checkToStringRadix(radix: Int) {
    if (radix < 2 || radix > 36) {
        throw IllegalArgumentException("radix $radix was not in valid range 2..36")
    }
}

private fun intToStringRadix(value: Int, radix: Int): String {
    checkToStringRadix(radix)
    if (value == 0) return "0"
    val negative = value < 0
    var n = if (value > 0) -value else value
    var result = ""
    while (n != 0) {
        val digit = -(n % radix)
        result = TO_STRING_RADIX_DIGITS[digit].toString() + result
        n /= radix
    }
    return if (negative) "-" + result else result
}

public fun Int.toString(radix: Int): String = intToStringRadix(this, radix)

private fun longToStringRadix(value: Long, radix: Int): String {
    checkToStringRadix(radix)
    if (value == 0L) return "0"
    val negative = value < 0L
    var n = if (value > 0L) -value else value
    val radixLong = radix.toLong()
    var result = ""
    while (n != 0L) {
        val digit = -(n % radixLong)
        result = TO_STRING_RADIX_DIGITS[digit.toInt()].toString() + result
        n /= radixLong
    }
    return if (negative) "-" + result else result
}

public fun Long.toString(radix: Int): String = longToStringRadix(this, radix)

// KUU-567: Unsigned radix conversion is source-backed as well. UInt, UByte,
// and UShort fit in the positive Long/Int domain, while ULong needs unsigned
// division so values with the high bit set are not interpreted as negative.
private fun uintToStringRadix(value: UInt, radix: Int): String {
    return longToStringRadix(value.toLong(), radix)
}

public fun UInt.toString(radix: Int): String = uintToStringRadix(this, radix)

public fun ULong.toString(radix: Int): String {
    checkToStringRadix(radix)
    if (this == 0uL) return "0"
    var n = this
    val radixULong = radix.toULong()
    var result = ""
    while (n != 0uL) {
        val digit = (n % radixULong).toInt()
        result = TO_STRING_RADIX_DIGITS[digit].toString() + result
        n /= radixULong
    }
    return result
}

public fun UByte.toString(radix: Int): String = uintToStringRadix(this + 0u, radix)

public fun UShort.toString(radix: Int): String = uintToStringRadix(this + 0u, radix)
