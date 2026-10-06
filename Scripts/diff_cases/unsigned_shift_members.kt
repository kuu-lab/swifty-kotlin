// KUU-1246: unsigned shl/shr and signed ushr remain builtin operations.
// Unsigned ushr calls must resolve user extensions, including safe calls.
infix fun UInt.ushr(bits: Int): Int = 42 + bits
infix fun ULong.ushr(bits: Int): Int = 43 + bits

fun main() {
    val ui = 0xFFFFFFFFu
    val ul = 0xFFFFFFFFFFFFFFFFuL
    println(ui shr 28)
    println(ui.shr(28))
    println(1u shl 31)
    println(1u.shl(31))
    println(ul shr 60)
    println(ul.shr(60))
    println(1uL shl 63)
    println(1uL.shl(63))
    println(-1 ushr 28)
    println((-1).ushr(28))
    println(-1L ushr 60)
    println((-1L).ushr(60))
    val ni: UInt? = ui
    val nl: ULong? = ul
    println(ni?.shr(28))
    println(nl?.shr(60))
    val smallUInt: UInt? = 1u
    val smallULong: ULong? = 1uL
    println(smallUInt?.shl(31))
    println(smallULong?.shl(63))
    val signedInt: Int? = -1
    val signedLong: Long? = -1L
    println(signedInt?.ushr(28))
    println(signedLong?.ushr(60))
    println(ui ushr 1)
    println(ul ushr 1)
    println(ui.ushr(2))
    println(ul.ushr(2))
    println(ni?.ushr(3))
    println(nl?.ushr(3))
    val absent: UInt? = null
    println(absent?.shr(4))
    println(absent?.ushr(4))
}
