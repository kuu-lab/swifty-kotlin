@file:kotlin.jvm.JvmName("NumbersKt")
package kotlin

@kotlin.internal.InlineOnly
public inline operator fun Int.inc(): Int = this + 1

@kotlin.internal.InlineOnly
public inline operator fun Int.dec(): Int = this - 1

@kotlin.internal.InlineOnly
public inline operator fun Long.inc(): Long = this + 1L

@kotlin.internal.InlineOnly
public inline operator fun Long.dec(): Long = this - 1L

@kotlin.internal.InlineOnly
public inline operator fun Byte.inc(): Byte = (this + 1).toByte()

@kotlin.internal.InlineOnly
public inline operator fun Byte.dec(): Byte = (this - 1).toByte()

@kotlin.internal.InlineOnly
public inline operator fun Short.inc(): Short = (this + 1).toShort()

@kotlin.internal.InlineOnly
public inline operator fun Short.dec(): Short = (this - 1).toShort()

@kotlin.internal.InlineOnly
public inline operator fun Float.inc(): Float = this + 1.0f

@kotlin.internal.InlineOnly
public inline operator fun Float.dec(): Float = this - 1.0f

@kotlin.internal.InlineOnly
public inline operator fun Double.inc(): Double = this + 1.0

@kotlin.internal.InlineOnly
public inline operator fun Double.dec(): Double = this - 1.0

@kotlin.internal.InlineOnly
public inline operator fun UInt.inc(): UInt = this + 1u

@kotlin.internal.InlineOnly
public inline operator fun UInt.dec(): UInt = this - 1u

@kotlin.internal.InlineOnly
public inline operator fun ULong.inc(): ULong = this + 1uL

@kotlin.internal.InlineOnly
public inline operator fun ULong.dec(): ULong = this - 1uL

@kotlin.internal.InlineOnly
public inline operator fun UByte.inc(): UByte = (this.toUInt() + 1u).toUByte()

@kotlin.internal.InlineOnly
public inline operator fun UByte.dec(): UByte = (this.toUInt() - 1u).toUByte()

@kotlin.internal.InlineOnly
public inline operator fun UShort.inc(): UShort = (this.toUInt() + 1u).toUShort()

@kotlin.internal.InlineOnly
public inline operator fun UShort.dec(): UShort = (this.toUInt() - 1u).toUShort()

public inline fun Double.isNaN(): Boolean = this != this
public inline fun Float.isNaN(): Boolean = this != this

public inline fun Double.isInfinite(): Boolean = this == Double.POSITIVE_INFINITY || this == Double.NEGATIVE_INFINITY
public inline fun Float.isInfinite(): Boolean = this == Float.POSITIVE_INFINITY || this == Float.NEGATIVE_INFINITY

public inline fun Double.isFinite(): Boolean = this == this && this != Double.POSITIVE_INFINITY && this != Double.NEGATIVE_INFINITY
public inline fun Float.isFinite(): Boolean = this == this && this != Float.POSITIVE_INFINITY && this != Float.NEGATIVE_INFINITY

public inline fun Int.countOneBits(): Int {
    var value = this
    value -= (value ushr 1) and 0x55555555
    value = (value and 0x33333333) + ((value ushr 2) and 0x33333333)
    value = (value + (value ushr 4)) and 0x0F0F0F0F
    value += value ushr 8
    value += value ushr 16
    return value and 0x3F
}

public inline fun Int.countLeadingZeroBits(): Int {
    var value = this
    value = value or (value ushr 1)
    value = value or (value ushr 2)
    value = value or (value ushr 4)
    value = value or (value ushr 8)
    value = value or (value ushr 16)
    return value.inv().countOneBits()
}

public inline fun Int.countTrailingZeroBits(): Int {
    if (this == 0) return 32
    return ((this and -this) - 1).countOneBits()
}

public inline fun Long.countOneBits(): Int {
    var value = this
    value -= (value ushr 1) and 0x5555555555555555L
    value = (value and 0x3333333333333333L) + ((value ushr 2) and 0x3333333333333333L)
    value = (value + (value ushr 4)) and 0x0F0F0F0F0F0F0F0FL
    value += value ushr 8
    value += value ushr 16
    value += value ushr 32
    return (value and 0x7FL).toInt()
}

public inline fun Long.countLeadingZeroBits(): Int {
    var value = this
    value = value or (value ushr 1)
    value = value or (value ushr 2)
    value = value or (value ushr 4)
    value = value or (value ushr 8)
    value = value or (value ushr 16)
    value = value or (value ushr 32)
    return value.inv().countOneBits()
}

public inline fun Long.countTrailingZeroBits(): Int {
    if (this == 0L) return 64
    return ((this and -this) - 1L).countOneBits()
}

public inline fun Int.rotateLeft(bitCount: Int): Int {
    val shift = bitCount and 31
    return (this shl shift) or (this ushr (32 - shift))
}

public inline fun Int.rotateRight(bitCount: Int): Int {
    val shift = bitCount and 31
    return (this ushr shift) or (this shl (32 - shift))
}

public inline fun Long.rotateLeft(bitCount: Int): Long {
    val shift = bitCount and 63
    return (this shl shift) or (this ushr (64 - shift))
}

public inline fun Long.rotateRight(bitCount: Int): Long {
    val shift = bitCount and 63
    return (this ushr shift) or (this shl (64 - shift))
}

public fun Float.toRawBits(): Int = 0
public fun Float.toBits(): Int = 0
public fun Double.toRawBits(): Long = 0L
public fun Double.toBits(): Long = 0L
