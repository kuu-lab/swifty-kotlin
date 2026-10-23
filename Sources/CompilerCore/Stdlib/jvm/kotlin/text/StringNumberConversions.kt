package kotlin.text

private const val JVM_RADIX_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

private fun intToStringRadix(value: Int, radix: Int): String {
    checkRadix(radix)
    if (value == 0) return "0"
    val negative = value < 0
    var number = if (negative) value else -value
    var result = ""
    while (number != 0) {
        val digit = -(number % radix)
        result = JVM_RADIX_DIGITS[digit].toString() + result
        number /= radix
    }
    return if (negative) "-$result" else result
}

private fun longToStringRadix(value: Long, radix: Int): String {
    checkRadix(radix)
    if (value == 0L) return "0"
    val negative = value < 0L
    var number = if (negative) value else -value
    val radixLong = radix.toLong()
    var result = ""
    while (number != 0L) {
        val digit = -(number % radixLong)
        result = JVM_RADIX_DIGITS[digit.toInt()].toString() + result
        number /= radixLong
    }
    return if (negative) "-$result" else result
}

private fun uintToStringRadix(value: UInt, radix: Int): String = longToStringRadix(value.toLong(), radix)

private fun ulongToStringRadix(value: ULong, radix: Int): String {
    checkRadix(radix)
    if (value == 0uL) return "0"
    var number = value
    val radixULong = radix.toULong()
    var result = ""
    while (number != 0uL) {
        val digit = (number % radixULong).toInt()
        result = JVM_RADIX_DIGITS[digit].toString() + result
        number /= radixULong
    }
    return result
}

public fun Byte.toString(radix: Int): String = intToStringRadix(this.toInt(), radix)

public fun Short.toString(radix: Int): String = intToStringRadix(this.toInt(), radix)

public fun Int.toString(radix: Int): String = intToStringRadix(this, radix)

public fun Long.toString(radix: Int): String = longToStringRadix(this, radix)

public fun UByte.toString(radix: Int): String = uintToStringRadix(this + 0u, radix)

public fun UShort.toString(radix: Int): String = uintToStringRadix(this + 0u, radix)

public fun UInt.toString(radix: Int): String = uintToStringRadix(this, radix)

public fun ULong.toString(radix: Int): String = ulongToStringRadix(this, radix)
