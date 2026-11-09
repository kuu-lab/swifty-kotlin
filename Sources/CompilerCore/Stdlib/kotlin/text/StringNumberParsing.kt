package kotlin.text

import kotlin.internal.KsSymbolName
import java.math.BigDecimal

@KsSymbolName("__kk_string_toFloat")
private external fun __kk_string_toFloat(str: String): Float

@KsSymbolName("__kk_string_toFloatOrNull")
private external fun __kk_string_toFloatOrNull(str: String): Float?

@KsSymbolName("__kk_string_toDouble")
private external fun __kk_string_toDouble(str: String): Double

@KsSymbolName("__kk_string_toDoubleOrNull")
private external fun __kk_string_toDoubleOrNull(str: String): Double?

@KsSymbolName("__kk_string_toBigDecimal")
private external fun __kk_string_toBigDecimal(str: String): BigDecimal

@KsSymbolName("__kk_string_toBigDecimalOrNull")
private external fun __kk_string_toBigDecimalOrNull(str: String): BigDecimal?

@KsSymbolName("__kk_string_toInt_radix")
private external fun __kk_string_toInt_radix(str: String, radix: Int): Int

@KsSymbolName("__kk_string_toIntOrNull_radix")
private external fun __kk_string_toIntOrNull_radix(str: String, radix: Int): Int?

@KsSymbolName("__kk_string_toLong_radix")
private external fun __kk_string_toLong_radix(str: String, radix: Int): Long

@KsSymbolName("__kk_string_toLongOrNull_radix")
private external fun __kk_string_toLongOrNull_radix(str: String, radix: Int): Long?

@KsSymbolName("__kk_string_toUIntOrNull_radix")
private external fun __kk_string_toUIntOrNull_radix(str: String, radix: Int): UInt?

@KsSymbolName("__kk_string_toULongOrNull_radix")
private external fun __kk_string_toULongOrNull_radix(str: String, radix: Int): ULong?

public fun String.toFloat(): Float {
    return __kk_string_toFloat(this)
}

public fun String.toFloatOrNull(): Float? {
    return __kk_string_toFloatOrNull(this)
}

public fun String.toDouble(): Double {
    return __kk_string_toDouble(this)
}

public fun String.toDoubleOrNull(): Double? {
    return __kk_string_toDoubleOrNull(this)
}

public fun String.toBigDecimal(): BigDecimal {
    return __kk_string_toBigDecimal(this)
}

public fun String.toBigDecimalOrNull(): BigDecimal? {
    return __kk_string_toBigDecimalOrNull(this)
}

public fun String.toInt(): Int = toInt(10)

public fun String.toInt(radix: Int): Int {
    return __kk_string_toInt_radix(this, radix)
}

public fun String.toIntOrNull(): Int? = toIntOrNull(10)

public fun String.toIntOrNull(radix: Int): Int? {
    return __kk_string_toIntOrNull_radix(this, radix)
}

public fun String.toLong(): Long = toLong(10)

public fun String.toLong(radix: Int): Long {
    return __kk_string_toLong_radix(this, radix)
}

public fun String.toLongOrNull(): Long? = toLongOrNull(10)

public fun String.toLongOrNull(radix: Int): Long? {
    return __kk_string_toLongOrNull_radix(this, radix)
}

public fun String.toShort(): Short = toShort(10)

// java.lang.Short.parseShort(s, radix): unparsable input reports the Int
// parse failure, out-of-range values report "Value out of range".
public fun String.toShort(radix: Int): Short {
    val value = toInt(radix)
    if (value < -32768 || value > 32767) {
        throw NumberFormatException("Value out of range. Value:\"$this\" Radix:$radix")
    }
    return value.toShort()
}

public fun String.toShortOrNull(): Short? = toShortOrNull(10)

public fun String.toShortOrNull(radix: Int): Short? {
    val value = toIntOrNull(radix) ?: return null
    if (value < -32768 || value > 32767) return null
    return value.toShort()
}

public fun String.toByte(): Byte = toByte(10)

public fun String.toByte(radix: Int): Byte {
    val value = toInt(radix)
    if (value < -128 || value > 127) {
        throw NumberFormatException("Value out of range. Value:\"$this\" Radix:$radix")
    }
    return value.toByte()
}

public fun String.toByteOrNull(): Byte? = toByteOrNull(10)

public fun String.toByteOrNull(radix: Int): Byte? {
    val value = toIntOrNull(radix) ?: return null
    if (value < -128 || value > 127) return null
    return value.toByte()
}

public fun String.toUByte(): UByte {
    return toUByteOrNull() ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toUByte(radix: Int): UByte {
    return toUByteOrNull(radix) ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toUByteOrNull(): UByte? = toUByteOrNull(10)

public fun String.toUByteOrNull(radix: Int): UByte? {
    val value = toUIntOrNull(radix) ?: return null
    if (value > 255u) return null
    return value.toUByte()
}

public fun String.toUShort(): UShort {
    return toUShortOrNull() ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toUShort(radix: Int): UShort {
    return toUShortOrNull(radix) ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toUShortOrNull(): UShort? = toUShortOrNull(10)

public fun String.toUShortOrNull(radix: Int): UShort? {
    val value = toUIntOrNull(radix) ?: return null
    if (value > 65535u) return null
    return value.toUShort()
}

public fun String.toUInt(): UInt {
    return toUIntOrNull() ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toUInt(radix: Int): UInt {
    return toUIntOrNull(radix) ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toUIntOrNull(): UInt? = toUIntOrNull(10)

public fun String.toUIntOrNull(radix: Int): UInt? {
    return __kk_string_toUIntOrNull_radix(this, radix)
}

public fun String.toULong(): ULong {
    return toULongOrNull() ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toULong(radix: Int): ULong {
    return toULongOrNull(radix) ?: throw NumberFormatException("Invalid number format: '$this'")
}

public fun String.toULongOrNull(): ULong? = toULongOrNull(10)

public fun String.toULongOrNull(radix: Int): ULong? {
    return __kk_string_toULongOrNull_radix(this, radix)
}

public fun String?.toBoolean(): Boolean =
    this != null && this.equals("true", ignoreCase = true)

public fun String.toBooleanStrict(): Boolean =
    when (this) {
        "true" -> true
        "false" -> false
        else -> throw IllegalArgumentException("The string doesn't represent a boolean value: $this")
    }

public fun String.toBooleanStrictOrNull(): Boolean? =
    when (this) {
        "true" -> true
        "false" -> false
        else -> null
    }
