class MyInt(val value: Int) : Number() {
    override fun toDouble(): Double = value.toDouble()
    override fun toFloat(): Float = value.toFloat()
    override fun toLong(): Long = value.toLong()
    override fun toInt(): Int = value.toInt()
    override fun toShort(): Short = value.toShort()
    override fun toByte(): Byte = value.toByte()
}

fun main() {
    val n: Number = MyInt(42)
    println(n.toDouble())
    println(n.toFloat())
    println(n.toLong())
    println(n.toInt())
    println(n.toShort())
    println(n.toByte())
}
