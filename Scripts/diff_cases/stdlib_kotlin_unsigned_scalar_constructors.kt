// DIFF_JVM
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    println(UByte((-1).toByte()).toInt())
    println(UShort((-1).toShort()).toInt())
    println(UInt(-1).toLong())
    println(ULong(-1L).toLong() == -1L)
    println(UByte(data = (-1).toByte()).toInt())
    println(UShort(data = (-1).toShort()).toInt())
    println(UInt(data = -1).toLong())
    println(ULong(data = -1L).toLong() == -1L)
}
