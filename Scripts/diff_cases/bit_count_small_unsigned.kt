// KUU-1098: Byte/Short/UByte/UShort/UInt/ULong bit-count and one-bit extensions.
private fun printByteBits(value: Byte) {
    println(value.countOneBits())
    println(value.countLeadingZeroBits())
    println(value.countTrailingZeroBits())
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

private fun printShortBits(value: Short) {
    println(value.countOneBits())
    println(value.countLeadingZeroBits())
    println(value.countTrailingZeroBits())
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

private fun printUByteBits(value: UByte) {
    println(value.countOneBits())
    println(value.countLeadingZeroBits())
    println(value.countTrailingZeroBits())
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

private fun printUShortBits(value: UShort) {
    println(value.countOneBits())
    println(value.countLeadingZeroBits())
    println(value.countTrailingZeroBits())
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

private fun printUIntBits(value: UInt) {
    println(value.countOneBits())
    println(value.countLeadingZeroBits())
    println(value.countTrailingZeroBits())
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

private fun printULongBits(value: ULong) {
    println(value.countOneBits())
    println(value.countLeadingZeroBits())
    println(value.countTrailingZeroBits())
    println(value.takeHighestOneBit())
    println(value.takeLowestOneBit())
}

fun main() {
    // Byte: zero, low bit set, all bits set, sign bit, and a mixed value.
    printByteBits(0.toByte())
    printByteBits(1.toByte())
    printByteBits((-1).toByte())
    printByteBits((-128).toByte())
    printByteBits(0x55.toByte())

    // Short: zero, low bit set, all bits set, sign bit, and a mixed value.
    printShortBits(0.toShort())
    printShortBits(1.toShort())
    printShortBits((-1).toShort())
    printShortBits((-32768).toShort())
    printShortBits(0x5555.toShort())

    // UByte: zero, low bit set, all bits set, high bit.
    printUByteBits(0u.toUByte())
    printUByteBits(1u.toUByte())
    printUByteBits(255u.toUByte())
    printUByteBits(128u.toUByte())

    // UShort: zero, low bit set, all bits set, high bit.
    printUShortBits(0u.toUShort())
    printUShortBits(1u.toUShort())
    printUShortBits(0xFFFFu.toUShort())
    printUShortBits(0x8000u.toUShort())

    // UInt: zero, low bit set, all bits set, high bit, and a mixed value.
    printUIntBits(0u)
    printUIntBits(1u)
    printUIntBits(0xFFFFFFFFu)
    printUIntBits(0x80000000u)
    printUIntBits(0x12345678u)

    // ULong: zero, low bit set, all bits set, high bit, and a mixed value.
    printULongBits(0uL)
    printULongBits(1uL)
    printULongBits(0xFFFFFFFFFFFFFFFFuL)
    printULongBits(0x8000000000000000uL)
    printULongBits(0x123456789ABCDEFuL)
}
