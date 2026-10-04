package golden.sema

class NumberChild : Number() {
    override fun toDouble(): Double = 42.0
    override fun toFloat(): Float = 42.0f
    override fun toLong(): Long = 42L
    override fun toInt(): Int = 42
    override fun toShort(): Short = 42
    override fun toByte(): Byte = 42
}
