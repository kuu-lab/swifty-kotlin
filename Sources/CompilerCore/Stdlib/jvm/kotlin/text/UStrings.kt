package kotlin.text

import kotlin.jvm.internal.__jvmCharDigit

private fun invalidUnsignedNumber(input: String): Nothing =
    throw NumberFormatException("Invalid number format: '$input'")

private fun parseUnsignedBits(input: String, radix: Int): Long? {
    checkRadix(radix)
    if (input.isEmpty()) return null
    var index = if (input[0] == '+') 1 else 0
    if (index == input.length) return null

    // Divide 2 * Long.MAX_VALUE + 1 by the radix without overflowing a signed Long.
    val base = radix.toLong()
    val doubledRemainder = 2L * (Long.MAX_VALUE % base) + 1L
    val maxBeforeMultiply = 2L * (Long.MAX_VALUE / base) + doubledRemainder / base
    val maxFinalDigit = doubledRemainder % base
    var bits = 0L
    while (index < input.length) {
        val digit = __jvmCharDigit(input[index], radix).toLong()
        if (digit < 0L || bits < 0L || bits > maxBeforeMultiply ||
            (bits == maxBeforeMultiply && digit > maxFinalDigit)) return null
        bits = bits * base + digit
        index++
    }
    return bits
}

public fun String.toUInt(): UInt = toUInt(10)
public fun String.toUInt(radix: Int): UInt = toUIntOrNull(radix) ?: invalidUnsignedNumber(this)
public fun String.toUIntOrNull(): UInt? = toUIntOrNull(10)
public fun String.toUIntOrNull(radix: Int): UInt? {
    val bits = parseUnsignedBits(this, radix) ?: return null
    return if (bits >= 0L && bits <= 4294967295L) bits.toUInt() else null
}

public fun String.toULong(): ULong = toULong(10)
public fun String.toULong(radix: Int): ULong = toULongOrNull(radix) ?: invalidUnsignedNumber(this)
public fun String.toULongOrNull(): ULong? = toULongOrNull(10)
public fun String.toULongOrNull(radix: Int): ULong? =
    parseUnsignedBits(this, radix)?.toULong()

public fun String.toUByte(): UByte = toUByte(10)
public fun String.toUByte(radix: Int): UByte = toUByteOrNull(radix) ?: invalidUnsignedNumber(this)
public fun String.toUByteOrNull(): UByte? = toUByteOrNull(10)
public fun String.toUByteOrNull(radix: Int): UByte? {
    val value = toUIntOrNull(radix) ?: return null
    return if (value <= 255u) value.toUByte() else null
}

public fun String.toUShort(): UShort = toUShort(10)
public fun String.toUShort(radix: Int): UShort = toUShortOrNull(radix) ?: invalidUnsignedNumber(this)
public fun String.toUShortOrNull(): UShort? = toUShortOrNull(10)
public fun String.toUShortOrNull(radix: Int): UShort? {
    val value = toUIntOrNull(radix) ?: return null
    return if (value <= 65535u) value.toUShort() else null
}

@kotlin.jvm.JvmName("toString-LxnNnR4")
internal fun formatUByte(value: UByte, radix: Int): String = value.toString(radix)

@kotlin.jvm.JvmName("toString-olVBNx4")
internal fun formatUShort(value: UShort, radix: Int): String = value.toString(radix)

@kotlin.jvm.JvmName("toString-V7xB4Y4")
internal fun formatUInt(value: UInt, radix: Int): String = value.toString(radix)

@kotlin.jvm.JvmName("toString-JSWoG40")
internal fun formatULong(value: ULong, radix: Int): String = value.toString(radix)
