fun main() {
    // UByte / UShort
    println(5.toUByte().coerceIn(1.toUByte(), 10.toUByte()).toInt())
    println(0.toUByte().coerceIn(1.toUByte(), 10.toUByte()).toInt())
    println(15.toUByte().coerceIn(1.toUByte(), 10.toUByte()).toInt())
    println(5.toUByte().coerceAtLeast(10.toUByte()).toInt())
    println(15.toUByte().coerceAtMost(10.toUByte()).toInt())

    println(500.toUShort().coerceIn(100.toUShort(), 900.toUShort()).toInt())
    println(50.toUShort().coerceIn(100.toUShort(), 900.toUShort()).toInt())
    println(1000.toUShort().coerceIn(100.toUShort(), 900.toUShort()).toInt())
    println(50.toUShort().coerceAtLeast(100.toUShort()).toInt())
    println(1000.toUShort().coerceAtMost(900.toUShort()).toInt())

    // UInt / ULong with values above Int.max to exercise unsigned comparison.
    val lowerUInt = Int.MAX_VALUE.toUInt() + 10u
    val upperUInt = lowerUInt + 20u
    val middleUInt = lowerUInt + 7u
    println(middleUInt.coerceIn(lowerUInt, upperUInt) == middleUInt)
    println((lowerUInt - 1u).coerceIn(lowerUInt, upperUInt) == lowerUInt)
    println((upperUInt + 1u).coerceIn(lowerUInt, upperUInt) == upperUInt)
    println((lowerUInt - 1u).coerceAtLeast(lowerUInt) == lowerUInt)
    println((upperUInt + 1u).coerceAtMost(upperUInt) == upperUInt)

    val lowerULong = Long.MAX_VALUE.toULong() + 10uL
    val upperULong = lowerULong + 20uL
    val middleULong = lowerULong + 7uL
    println(middleULong.coerceIn(lowerULong, upperULong) == middleULong)
    println((lowerULong - 1uL).coerceIn(lowerULong, upperULong) == lowerULong)
    println((upperULong + 1uL).coerceIn(lowerULong, upperULong) == upperULong)
    println((lowerULong - 1uL).coerceAtLeast(lowerULong) == lowerULong)
    println((upperULong + 1uL).coerceAtMost(upperULong) == upperULong)

    // Range overloads for UInt / ULong.
    val uintRange = lowerUInt..upperUInt
    println(middleUInt.coerceIn(uintRange) == middleUInt)
    val ulongRange = lowerULong..upperULong
    println(middleULong.coerceIn(ulongRange) == middleULong)
}
