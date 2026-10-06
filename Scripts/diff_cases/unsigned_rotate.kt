fun printUIntRotations(value: UInt, count: Int) {
    println(value.rotateLeft(count))
    println(value.rotateRight(count))
}

fun printULongRotations(value: ULong, count: Int) {
    println(value.rotateLeft(count))
    println(value.rotateRight(count))
}

fun main() {
    printUIntRotations(0xFF000000u, 4)
    printULongRotations(0xFF00000000000000uL, 4)
    printUIntRotations(0u, 0)
    printUIntRotations(1u, 0)
    printUIntRotations(1u, 1)
    printUIntRotations(1u, 31)
    printUIntRotations(1u, 32)
    printUIntRotations(1u, 33)
    printUIntRotations(1u, -1)
    printUIntRotations(1u, Int.MIN_VALUE)
    printUIntRotations(1u, 2147483647)
    printUIntRotations(4294967295u, 5)
    printUIntRotations(2147483648u, 1)
    printULongRotations(0uL, 0)
    printULongRotations(1uL, 0)
    printULongRotations(1uL, 1)
    printULongRotations(1uL, 63)
    printULongRotations(1uL, 64)
    printULongRotations(1uL, 65)
    printULongRotations(1uL, -1)
    printULongRotations(1uL, Int.MIN_VALUE)
    printULongRotations(1uL, 2147483647)
    printULongRotations(18446744073709551615uL, 5)
    printULongRotations(9223372036854775808uL, 1)
    val ui: UInt? = 0xFF000000u
    val ul: ULong? = 0xFF00000000000000uL
    println(ui?.rotateLeft(4))
    println(ui?.rotateRight(4))
    println(ul?.rotateLeft(4))
    println(ul?.rotateRight(4))
    val missingUInt: UInt? = null
    val missingULong: ULong? = null
    println(missingUInt?.rotateLeft(1))
    println(missingULong?.rotateRight(1))
}
