import java.math.BigDecimal

private class JSONDecimal(private val value: BigDecimal) : Number() {
    override fun toDouble(): Double = value.toDouble()
    override fun toFloat(): Float = value.toFloat()
    override fun toLong(): Long = value.toLong()
    override fun toInt(): Int = value.toInt()
    override fun toShort(): Short = value.toShort()
    override fun toByte(): Byte = value.toByte()
}

private fun asDouble(value: BigDecimal): Double = value.toDouble()
private fun asFloat(value: BigDecimal): Float = value.toFloat()
private fun asLong(value: BigDecimal): Long = value.toLong()
private fun asInt(value: BigDecimal): Int = value.toInt()
private fun asShort(value: BigDecimal): Short = value.toShort()
private fun asByte(value: BigDecimal): Byte = value.toByte()

private fun printConversions(value: BigDecimal) {
    println("${asDouble(value).toRawBits()}|${asFloat(value).toRawBits()}|${asLong(value)}|${asInt(value)}|${asShort(value)}|${asByte(value)}")
    val number: Number = JSONDecimal(value)
    println("${number.toDouble().toRawBits()}|${number.toFloat().toRawBits()}|${number.toLong()}|${number.toInt()}|${number.toShort()}|${number.toByte()}")
}

fun main() {
    for (text in listOf(
        "0.1",
        "-0.0",
        "-1e-400",
        "1e400",
        "-1e400",
        "123.987",
        "-129.9",
        "32768.9",
        "9223372036854775808.9",
        "18446744073709551617.9"
    )) {
        printConversions(text.toBigDecimal())
    }

    val asNumber: Number = "123.987".toBigDecimal()
    println("${asNumber.toDouble().toRawBits()}|${asNumber.toFloat().toRawBits()}|${asNumber.toLong()}|${asNumber.toInt()}|${asNumber.toShort()}|${asNumber.toByte()}")

    val first = "1.0".toBigDecimal()
    println("${first.compareTo("1.00".toBigDecimal())}|${first.toString()}")
}
