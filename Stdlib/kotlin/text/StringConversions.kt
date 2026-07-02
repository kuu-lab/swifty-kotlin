package kotlin.text

import kswiftk.internal.*

// MARK: - Numeric conversions (runtime-backed)

fun String.toInt(): Int = __string_toInt_flat(this)

fun String.toInt(radix: Int): Int = __string_toInt_radix_flat(this, radix)

fun String.toIntOrNull(): Int? = __string_toIntOrNull_flat(this)

fun String.toIntOrNull(radix: Int): Int? = __string_toIntOrNull_radix_flat(this, radix)

fun String.toLong(): Long = __string_toLong_flat(this)

fun String.toLongOrNull(): Long? = __string_toLongOrNull_flat(this)

fun String.toFloat(): Float = __string_toFloat_flat(this)

fun String.toFloatOrNull(): Float? = __string_toFloatOrNull_flat(this)

fun String.toDouble(): Double = __string_toDouble_flat(this)

fun String.toDoubleOrNull(): Double? = __string_toDoubleOrNull_flat(this)

fun String.toShort(): Short = __string_toShort_flat(this)

fun String.toShortOrNull(): Short? = __string_toShortOrNull_flat(this)

fun String.toByte(): Byte = __string_toByte_flat(this)

fun String.toByte(radix: Int): Byte = __string_toByte_radix_flat(this, radix)

fun String.toByteOrNull(): Byte? = __string_toByteOrNull_flat(this)

fun String.toUByteOrNull(radix: Int): UByte? = __string_toUByteOrNull_radix_flat(this, radix)

fun String.toUByteOrNull(): UByte? = this.toUByteOrNull(10)

fun String.toUShortOrNull(radix: Int): UShort? = __string_toUShortOrNull_radix_flat(this, radix)

fun String.toUShortOrNull(): UShort? = this.toUShortOrNull(10)

fun String.toUIntOrNull(radix: Int): UInt? = __string_toUIntOrNull_radix_flat(this, radix)

fun String.toUIntOrNull(): UInt? = this.toUIntOrNull(10)

fun String.toULongOrNull(radix: Int): ULong? = __string_toULongOrNull_radix_flat(this, radix)

fun String.toULongOrNull(): ULong? = this.toULongOrNull(10)

// MARK: - Boolean conversions (runtime-backed)

fun String?.toBoolean(): Boolean = __string_toBoolean_flat(this)

fun String.toBooleanStrict(): Boolean = __string_toBooleanStrict_flat(this)

fun String.toBooleanStrictOrNull(): Boolean? = __string_toBooleanStrictOrNull_flat(this)
