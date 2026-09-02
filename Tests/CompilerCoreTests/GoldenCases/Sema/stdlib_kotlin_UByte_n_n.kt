@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

fun main(): UByte {
    val zero = UByte(0.toByte())
    val max = UByte(127.toByte())
    val allBits = UByte((-1).toByte())
    val min = UByte(Byte.MIN_VALUE.toByte())
    val inferred: UByte = UByte(0.toByte())
    val boxed: Any = allBits
    return if (zero.toInt() == 0 && max.toInt() == 127 && min.toInt() == 128
        && inferred.toInt() == 0 && boxed is UByte) allBits else zero
}
