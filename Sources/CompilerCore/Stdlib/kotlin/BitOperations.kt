package kotlin

// KSP-643: countOneBits / countLeadingZeroBits / countTrailingZeroBits.
// Pure Kotlin implementations for Int and Long (SWAR popcount).

public fun Int.countOneBits(): Int {
    var v = this
    v -= (v ushr 1) and 0x55555555
    v = (v and 0x33333333) + ((v ushr 2) and 0x33333333)
    v = (v + (v ushr 4)) and 0x0F0F0F0F
    v += v ushr 8
    v += v ushr 16
    return v and 0x3F
}

public fun Int.countLeadingZeroBits(): Int {
    var v = this
    v = v or (v ushr 1)
    v = v or (v ushr 2)
    v = v or (v ushr 4)
    v = v or (v ushr 8)
    v = v or (v ushr 16)
    return v.inv().countOneBits()
}

public fun Int.countTrailingZeroBits(): Int {
    if (this == 0) return 32
    return ((this and (-this)) - 1).countOneBits()
}

public fun Long.countOneBits(): Int {
    var v = this
    v -= (v ushr 1) and 0x5555555555555555L
    v = (v and 0x3333333333333333L) + ((v ushr 2) and 0x3333333333333333L)
    v = (v + (v ushr 4)) and 0x0F0F0F0F0F0F0F0FL
    v += v ushr 8
    v += v ushr 16
    v += v ushr 32
    return (v and 0x7FL).toInt()
}

public fun Long.countLeadingZeroBits(): Int {
    var v = this
    v = v or (v ushr 1)
    v = v or (v ushr 2)
    v = v or (v ushr 4)
    v = v or (v ushr 8)
    v = v or (v ushr 16)
    v = v or (v ushr 32)
    return v.inv().countOneBits()
}

public fun Long.countTrailingZeroBits(): Int {
    if (this == 0L) return 64
    return ((this and (-this)) - 1L).countOneBits()
}

// KSP-644: highest/lowest one-bit operations are source-backed extensions.

public fun Int.highestOneBit(): Int {
    if (this == 0) return 0
    if (this < 0) return Int.MIN_VALUE
    return 1 shl (31 - countLeadingZeroBits())
}

public fun Int.lowestOneBit(): Int = this and (-this)

public fun Int.takeHighestOneBit(): Int = highestOneBit()

public fun Int.takeLowestOneBit(): Int = lowestOneBit()

public fun Long.highestOneBit(): Long {
    if (this == 0L) return 0L
    if (this < 0L) return Long.MIN_VALUE
    return 1L shl (63 - countLeadingZeroBits())
}

public fun Long.lowestOneBit(): Long = this and (-this)

public fun Long.takeHighestOneBit(): Long = highestOneBit()

public fun Long.takeLowestOneBit(): Long = lowestOneBit()

// KUU-1098: bit-count and one-bit extensions for the remaining integer types,
// mirroring the real Kotlin stdlib formulas (operands masked to their width).

public fun Byte.countOneBits(): Int = (toInt() and 0xFF).countOneBits()

public fun Byte.countLeadingZeroBits(): Int =
    (toInt() and 0xFF).countLeadingZeroBits() - (Int.SIZE_BITS - Byte.SIZE_BITS)

public fun Byte.countTrailingZeroBits(): Int = (toInt() or 0x100).countTrailingZeroBits()

public fun Byte.takeHighestOneBit(): Byte = (toInt() and 0xFF).takeHighestOneBit().toByte()

public fun Byte.takeLowestOneBit(): Byte = toInt().takeLowestOneBit().toByte()

public fun Short.countOneBits(): Int = (toInt() and 0xFFFF).countOneBits()

public fun Short.countLeadingZeroBits(): Int =
    (toInt() and 0xFFFF).countLeadingZeroBits() - (Int.SIZE_BITS - Short.SIZE_BITS)

public fun Short.countTrailingZeroBits(): Int = (toInt() or 0x10000).countTrailingZeroBits()

public fun Short.takeHighestOneBit(): Short = (toInt() and 0xFFFF).takeHighestOneBit().toShort()

public fun Short.takeLowestOneBit(): Short = toInt().takeLowestOneBit().toShort()

public fun UInt.countOneBits(): Int = toInt().countOneBits()

public fun UInt.countLeadingZeroBits(): Int = toInt().countLeadingZeroBits()

public fun UInt.countTrailingZeroBits(): Int = toInt().countTrailingZeroBits()

public fun UInt.takeHighestOneBit(): UInt = toInt().takeHighestOneBit().toUInt()

public fun UInt.takeLowestOneBit(): UInt = toInt().takeLowestOneBit().toUInt()

public fun ULong.countOneBits(): Int = toLong().countOneBits()

public fun ULong.countLeadingZeroBits(): Int = toLong().countLeadingZeroBits()

public fun ULong.countTrailingZeroBits(): Int = toLong().countTrailingZeroBits()

public fun ULong.takeHighestOneBit(): ULong = toLong().takeHighestOneBit().toULong()

public fun ULong.takeLowestOneBit(): ULong = toLong().takeLowestOneBit().toULong()

public fun UByte.countOneBits(): Int = toUInt().countOneBits()

public fun UByte.countLeadingZeroBits(): Int = toByte().countLeadingZeroBits()

public fun UByte.countTrailingZeroBits(): Int = toByte().countTrailingZeroBits()

public fun UByte.takeHighestOneBit(): UByte = toInt().takeHighestOneBit().toUByte()

public fun UByte.takeLowestOneBit(): UByte = toInt().takeLowestOneBit().toUByte()

public fun UShort.countOneBits(): Int = toUInt().countOneBits()

public fun UShort.countLeadingZeroBits(): Int = toShort().countLeadingZeroBits()

public fun UShort.countTrailingZeroBits(): Int = toShort().countTrailingZeroBits()

public fun UShort.takeHighestOneBit(): UShort = toInt().takeHighestOneBit().toUShort()

public fun UShort.takeLowestOneBit(): UShort = toInt().takeLowestOneBit().toUShort()
