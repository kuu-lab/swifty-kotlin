@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    val zero = UByte(0.toByte())
    val max = UByte(127.toByte())
    val allBits = UByte((-1).toByte())
    val min = UByte(Byte.MIN_VALUE.toByte())
    val inferred: UByte = UByte(0.toByte())
    val boxed: Any = allBits
    println(zero.toInt())
    println(max.toInt())
    println(allBits.toInt())
    println(min.toInt())
    println(inferred.toInt())
    println(boxed is UByte)
    println((boxed as UByte).toInt())
}
