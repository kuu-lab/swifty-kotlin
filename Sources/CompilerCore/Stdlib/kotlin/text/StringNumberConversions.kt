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

// KSP-1362: the Int/Long bodies now live in the `kotlin.text.intToString` /
// `longToString` / `checkRadix` top-level functions (Stdlib.kt), matching the
// real stdlib ABI.
public fun Int.toString(radix: Int): String = intToString(this, radix)

public fun Long.toString(radix: Int): String = longToString(this, radix)

// KUU-567: Unsigned radix conversion is source-backed as well. UInt, UByte,
// and UShort fit in the positive Long/Int domain, while ULong needs unsigned
// division so values with the high bit set are not interpreted as negative.
private fun uintToStringRadix(value: UInt, radix: Int): String {
    return longToString(value.toLong(), radix)
}

public fun UInt.toString(radix: Int): String = uintToStringRadix(this, radix)

public fun ULong.toString(radix: Int): String {
    checkRadix(radix)
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
