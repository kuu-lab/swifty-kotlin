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
        throw IllegalArgumentException("radix $radix is out of the valid range 2..36")
    }
}

public fun Int.toString(radix: Int): String {
    checkToStringRadix(radix)
    if (this == 0) return "0"
    val negative = this < 0
    var n = if (this > 0) -this else this
    var result = ""
    while (n != 0) {
        val digit = -(n % radix)
        result = TO_STRING_RADIX_DIGITS[digit].toString() + result
        n /= radix
    }
    return if (negative) "-" + result else result
}

public fun Long.toString(radix: Int): String {
    checkToStringRadix(radix)
    if (this == 0L) return "0"
    val negative = this < 0L
    var n = if (this > 0L) -this else this
    val radixLong = radix.toLong()
    var result = ""
    while (n != 0L) {
        val digit = -(n % radixLong)
        result = TO_STRING_RADIX_DIGITS[digit.toInt()].toString() + result
        n /= radixLong
    }
    return if (negative) "-" + result else result
}
