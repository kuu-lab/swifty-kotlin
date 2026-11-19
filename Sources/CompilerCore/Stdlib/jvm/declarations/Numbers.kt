package kotlin
abstract class Number {
    abstract fun toByte(): Byte
    abstract fun toShort(): Short
    abstract fun toInt(): Int
    abstract fun toLong(): Long
    abstract fun toFloat(): Float
    abstract fun toDouble(): Double
}

@Deprecated(
    "Conversion of Char to Number is deprecated. Use Char.code property instead.",
    ReplaceWith("this.code.toByte()")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public inline fun Char.toByte(): Byte = this.code.toByte()

public fun Double.toRawBits(): Long = null!!
public fun Double.toBits(): Long = null!!
public fun Float.toRawBits(): Int = null!!
public fun Float.toBits(): Int = null!!
