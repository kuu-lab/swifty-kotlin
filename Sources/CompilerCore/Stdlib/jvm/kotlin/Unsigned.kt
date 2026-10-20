@file:kotlin.jvm.JvmName("UnsignedKt")
package kotlin
import kotlin.jvm.internal.*
import kotlin.text.checkRadix
fun uintToDouble(value: Int): Double = (value.toLong() and 4294967295L).toDouble()
fun ulongToDouble(value: Long): Double = (value ushr 11).toDouble() * 2048.0 + (value and 2047L).toDouble()
fun doubleToUInt(value: Double): Int {
    if (value != value || value <= 0.0) return 0
    if (value >= 4294967295.0) return -1
    return value.toLong().toInt()
}
fun doubleToULong(value: Double): Long {
    if (value != value || value <= 0.0) return 0L
    if (value >= 18446744073709551616.0) return -1L
    if (value < 9223372036854775808.0) return value.toLong()
    return (value - 9223372036854775808.0).toLong() or Long.MIN_VALUE
}

fun uintCompare(first: Int, second: Int): Int = __jvmUIntCompare(first, second)
fun ulongCompare(first: Long, second: Long): Int = __jvmULongCompare(first, second)
@kotlin.jvm.JvmName("uintDivide-J1ME1BU")
fun uintDivide(first: Int, second: Int): Int = __jvmUIntDivide(first, second)
@kotlin.jvm.JvmName("uintRemainder-J1ME1BU")
fun uintRemainder(first: Int, second: Int): Int = __jvmUIntRemainder(first, second)
@kotlin.jvm.JvmName("ulongDivide-eb3DHEI")
fun ulongDivide(first: Long, second: Long): Long = __jvmULongDivide(first, second)
@kotlin.jvm.JvmName("ulongRemainder-eb3DHEI")
fun ulongRemainder(first: Long, second: Long): Long = __jvmULongRemainder(first, second)
fun ulongToString(value: Long, radix: Int): String = __jvmULongStringRadix(value, checkRadix(radix))
