@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

class NumberProbe(private val value: Int) : Number() {
    override fun toByte(): Byte = value.toByte()
    override fun toChar(): Char = value.toChar()
    override fun toDouble(): Double = value.toDouble()
    override fun toFloat(): Float = value.toFloat()
    override fun toInt(): Int = value
    override fun toLong(): Long = value.toLong()
    override fun toShort(): Short = value.toShort()
}

fun main() {
    val n: Number = NumberProbe(42)
    println(n.toByte())
    println(n.toChar().code)
    println(n.toDouble())
    println(n.toFloat())
    println(n.toInt())
    println(n.toLong())
    println(n.toShort())
}
