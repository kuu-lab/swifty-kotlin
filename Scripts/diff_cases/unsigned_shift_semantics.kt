fun main() {
    println(0xFFFFFFFFu shl 4)
    println(1u shl 32)
    println(ULong.MAX_VALUE shr 1)
    val u: UInt = 0x80000000u
    println(u shr 31)
    println(u shl 1)
    println(1u shl 33)
    println(ULong.MAX_VALUE shl 64)
    println(1uL shl 65)
    println(ULong.MAX_VALUE shr 63)
    println(ULong.MAX_VALUE shr 64)
    val n = 35
    println(0xFFFFFFFFu shr n)
    println(0xF0u.shl(28))
}
