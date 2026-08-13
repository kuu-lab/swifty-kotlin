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

@KsSymbolName("__kk_string_toInt")
private external fun __kk_string_toInt(str: String): Int

@KsSymbolName("__kk_string_toInt_radix")
private external fun __kk_string_toInt_radix(str: String, radix: Int): Int

@KsSymbolName("__kk_string_toIntOrNull")
private external fun __kk_string_toIntOrNull(str: String): Int?

@KsSymbolName("__kk_string_toIntOrNull_radix")
private external fun __kk_string_toIntOrNull_radix(str: String, radix: Int): Int?

@KsSymbolName("__kk_string_toLong")
private external fun __kk_string_toLong(str: String): Long

@KsSymbolName("__kk_string_toLongOrNull")
private external fun __kk_string_toLongOrNull(str: String): Long?

@KsSymbolName("__kk_string_toShort")
private external fun __kk_string_toShort(str: String): Short

@KsSymbolName("__kk_string_toShortOrNull")
private external fun __kk_string_toShortOrNull(str: String): Short?

@KsSymbolName("__kk_string_toByte")
private external fun __kk_string_toByte(str: String): Byte

@KsSymbolName("__kk_string_toByte_radix")
private external fun __kk_string_toByte_radix(str: String, radix: Int): Byte

@KsSymbolName("__kk_string_toByteOrNull")
private external fun __kk_string_toByteOrNull(str: String): Byte?

@KsSymbolName("__kk_string_toUByteOrNull")
private external fun __kk_string_toUByteOrNull(str: String): UByte?

@KsSymbolName("__kk_string_toUByteOrNull_radix")
private external fun __kk_string_toUByteOrNull_radix(str: String, radix: Int): UByte?

@KsSymbolName("__kk_string_toUShortOrNull")
private external fun __kk_string_toUShortOrNull(str: String): UShort?

@KsSymbolName("__kk_string_toUShortOrNull_radix")
private external fun __kk_string_toUShortOrNull_radix(str: String, radix: Int): UShort?

@KsSymbolName("__kk_string_toUIntOrNull")
private external fun __kk_string_toUIntOrNull(str: String): UInt?

@KsSymbolName("__kk_string_toUIntOrNull_radix")
private external fun __kk_string_toUIntOrNull_radix(str: String, radix: Int): UInt?

@KsSymbolName("__kk_string_toULongOrNull")
private external fun __kk_string_toULongOrNull(str: String): ULong?

@KsSymbolName("__kk_string_toULongOrNull_radix")
private external fun __kk_string_toULongOrNull_radix(str: String, radix: Int): ULong?

@KsSymbolName("__kk_string_toBoolean")
private external fun __kk_string_toBoolean(str: String?): Boolean

@KsSymbolName("__kk_string_toBooleanStrict")
private external fun __kk_string_toBooleanStrict(str: String): Boolean

@KsSymbolName("__kk_string_toBooleanStrictOrNull")
private external fun __kk_string_toBooleanStrictOrNull(str: String): Boolean?

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

public fun String.toInt(): Int {
    return __kk_string_toInt(this)
}

public fun String.toInt(radix: Int): Int {
    return __kk_string_toInt_radix(this, radix)
}

public fun String.toIntOrNull(): Int? {
    return __kk_string_toIntOrNull(this)
}

public fun String.toIntOrNull(radix: Int): Int? {
    return __kk_string_toIntOrNull_radix(this, radix)
}

public fun String.toLong(): Long {
    return __kk_string_toLong(this)
}

public fun String.toLongOrNull(): Long? {
    return __kk_string_toLongOrNull(this)
}

public fun String.toShort(): Short {
    return __kk_string_toShort(this)
}

public fun String.toShortOrNull(): Short? {
    return __kk_string_toShortOrNull(this)
}

public fun String.toByte(): Byte {
    return __kk_string_toByte(this)
}

public fun String.toByte(radix: Int): Byte {
    return __kk_string_toByte_radix(this, radix)
}

public fun String.toByteOrNull(): Byte? {
    return __kk_string_toByteOrNull(this)
}

public fun String.toUByteOrNull(): UByte? {
    return __kk_string_toUByteOrNull(this)
}

public fun String.toUByteOrNull(radix: Int): UByte? {
    return __kk_string_toUByteOrNull_radix(this, radix)
}

public fun String.toUShortOrNull(): UShort? {
    return __kk_string_toUShortOrNull(this)
}

public fun String.toUShortOrNull(radix: Int): UShort? {
    return __kk_string_toUShortOrNull_radix(this, radix)
}

public fun String.toUIntOrNull(): UInt? {
    return __kk_string_toUIntOrNull(this)
}

public fun String.toUIntOrNull(radix: Int): UInt? {
    return __kk_string_toUIntOrNull_radix(this, radix)
}

public fun String.toULongOrNull(): ULong? {
    return __kk_string_toULongOrNull(this)
}

public fun String.toULongOrNull(radix: Int): ULong? {
    return __kk_string_toULongOrNull_radix(this, radix)
}

public fun String?.toBoolean(): Boolean {
    return __kk_string_toBoolean(this)
}

public fun String.toBooleanStrict(): Boolean {
    return __kk_string_toBooleanStrict(this)
}

public fun String.toBooleanStrictOrNull(): Boolean? {
    return __kk_string_toBooleanStrictOrNull(this)
}
