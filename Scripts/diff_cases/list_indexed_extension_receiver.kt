fun Byte.widthLeadingZeros(): Int = (toInt() and 0xFF).countLeadingZeroBits() - 24
fun Byte.widthOneBits(): Int = (toInt() and 0xFF).countOneBits()
fun Short.widthLeadingZeros(): Int = (toInt() and 0xFFFF).countLeadingZeroBits() - 16
fun Short.widthOneBits(): Int = (toInt() and 0xFFFF).countOneBits()
fun UByte.widthLeadingZeros(): Int = toByte().widthLeadingZeros()
fun UByte.widthOneBits(): Int = toByte().widthOneBits()
fun UShort.widthLeadingZeros(): Int = toShort().widthLeadingZeros()
fun UShort.widthOneBits(): Int = toShort().widthOneBits()
fun Int.widthLeadingZeros(): Int = countLeadingZeroBits()
fun Int.widthOneBits(): Int = countOneBits()
fun Long.widthLeadingZeros(): Int = countLeadingZeroBits()
fun Long.widthOneBits(): Int = countOneBits()
fun UInt.widthLeadingZeros(): Int = toInt().countLeadingZeroBits()
fun UInt.widthOneBits(): Int = toInt().countOneBits()
fun ULong.widthLeadingZeros(): Int = toLong().countLeadingZeroBits()
fun ULong.widthOneBits(): Int = toLong().countOneBits()
fun Float.receiverValue(): Float = this
fun Double.receiverValue(): Double = this
fun Char.receiverValue(): Char = this
fun Boolean.receiverValue(): Boolean = this

fun main() {
    val shorts = listOf(0xF0.toShort(), (-1).toShort())
    println(shorts[0].widthLeadingZeros())
    println(shorts[1].widthOneBits())
    val short: Short = shorts[0]
    println(short.widthLeadingZeros())
    println(arrayOf(0xF0.toShort())[0].widthLeadingZeros())
    println(shorts.map { it.widthLeadingZeros() })
    println(mutableListOf(0xF0.toShort())[0].widthLeadingZeros())
    println(listOf(256.toShort())[0].widthLeadingZeros())
    println(listOf(Short.MIN_VALUE)[0].widthOneBits())

    val bytes = listOf(0x70.toByte(), (-1).toByte())
    println(bytes[0].widthLeadingZeros())
    println(bytes[1].widthOneBits())
    val ubytes = listOf(0xF0.toUByte(), 0xFF.toUByte())
    println(ubytes[0].widthLeadingZeros())
    println(ubytes[1].widthOneBits())
    val ushorts = listOf(0xF0.toUShort(), 0xFFFF.toUShort())
    println(ushorts[0].widthLeadingZeros())
    println(ushorts[1].widthOneBits())
    val ints = listOf(0xF0, -1)
    println(ints[0].widthLeadingZeros())
    println(ints[1].widthOneBits())
    val longs = listOf(0xF0L, -1L)
    println(longs[0].widthLeadingZeros())
    println(longs[1].widthOneBits())
    val uints = listOf(0xF0u, UInt.MAX_VALUE)
    println(uints[0].widthLeadingZeros())
    println(uints[1].widthOneBits())
    val ulongs = listOf(0xF0uL, ULong.MAX_VALUE)
    println(ulongs[0].widthLeadingZeros())
    println(ulongs[1].widthOneBits())

    val nullableShorts = listOf<Short?>(null, 0xF0.toShort())
    println(nullableShorts[0]?.widthLeadingZeros())
    println(nullableShorts[1]?.widthLeadingZeros())
    println(listOf("short")[0].length)
    println(listOf(1.5f)[0].receiverValue())
    println(listOf(-0.0)[0].receiverValue())
    println(listOf('x')[0].receiverValue())
    println(listOf(true)[0].receiverValue())
    try {
        println(shorts[2].widthLeadingZeros())
    } catch (e: IndexOutOfBoundsException) {
        println("out of bounds")
    }
}
