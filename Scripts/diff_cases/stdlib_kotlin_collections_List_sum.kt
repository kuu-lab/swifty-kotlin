fun main() {
    println(listOf(1.toByte(), 2.toByte(), 3.toByte()).sum())
    println(listOf(4.toShort(), 5.toShort()).sum())
    println(listOf(6, 7).sum())
    println(listOf(8L, 9L).sum())
    println(listOf(1.5f, 2.25f).sum())
    println(listOf(3.5, 4.25).sum())
    println(listOf(10.toUByte(), 11.toUByte()).sum())
    println(listOf(12.toUShort(), 13.toUShort()).sum())
    println(listOf(14u, 15u).sum())
    println(listOf(16uL, 17uL).sum())

    val emptyUInt: List<UInt> = listOf()
    println(emptyUInt.sum())

    val uintOverflow: List<UInt> = listOf(UInt.MAX_VALUE, 1u)
    println(uintOverflow.sum())
}
