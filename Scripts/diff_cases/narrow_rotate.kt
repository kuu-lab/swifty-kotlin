fun printNarrowRotations(value: Int, count: Int) {
    val b: Byte = value.toByte()
    val s: Short = value.toShort()
    val ub: UByte = value.toUByte()
    val us: UShort = value.toUShort()
    println(b.rotateLeft(bitCount = count))
    println(b.rotateRight(bitCount = count))
    println(s.rotateLeft(bitCount = count))
    println(s.rotateRight(bitCount = count))
    println(ub.rotateLeft(bitCount = count))
    println(ub.rotateRight(bitCount = count))
    println(us.rotateLeft(bitCount = count))
    println(us.rotateRight(bitCount = count))
}

fun main() {
    // Zero, all bits, sign bits, mixed bits, and signed maxima at both widths.
    for (value in listOf(0, 1, -1, 128, 32768, 0x81A5, 127, 32767)) {
        for (count in listOf(0, 1, 7, 8, 9, 15, 16, 17, 32, -1, -9, -17, Int.MIN_VALUE, Int.MAX_VALUE)) {
            printNarrowRotations(value, count)
        }
    }

    val b: Byte? = (-128).toByte()
    val s: Short? = (-32768).toShort()
    val ub: UByte? = 128.toUByte()
    val us: UShort? = 32768.toUShort()
    println(b?.rotateLeft(1))
    println(b?.rotateRight(1))
    println(s?.rotateLeft(1))
    println(s?.rotateRight(1))
    println(ub?.rotateLeft(1))
    println(ub?.rotateRight(1))
    println(us?.rotateLeft(1))
    println(us?.rotateRight(1))
    val missingByte: Byte? = null
    val missingShort: Short? = null
    val missingUByte: UByte? = null
    val missingUShort: UShort? = null
    println(missingByte?.rotateLeft(1))
    println(missingByte?.rotateRight(1))
    println(missingShort?.rotateLeft(1))
    println(missingShort?.rotateRight(1))
    println(missingUByte?.rotateLeft(1))
    println(missingUByte?.rotateRight(1))
    println(missingUShort?.rotateLeft(1))
    println(missingUShort?.rotateRight(1))
}
