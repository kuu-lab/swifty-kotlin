class ByteBounds(
    override val start: Byte,
    override val endInclusive: Byte,
) : ClosedRange<Byte>

class ShortBounds(
    override val start: Short,
    override val endInclusive: Short,
) : ClosedRange<Short>

class IntBounds(
    override val start: Int,
    override val endInclusive: Int,
) : ClosedRange<Int>

class LongBounds(
    override val start: Long,
    override val endInclusive: Long,
) : ClosedRange<Long>

class FloatBounds(
    override val start: Float,
    override val endInclusive: Float,
) : ClosedRange<Float>

class DoubleBounds(
    override val start: Double,
    override val endInclusive: Double,
) : ClosedRange<Double>

fun main() {
    val byteRange: ClosedRange<Byte> = ByteBounds(2, 4)
    println(byteRange.contains(3))
    println(byteRange.contains(260))
    println(byteRange.contains(4L))
    println(byteRange.contains(5L))
    println(byteRange.contains(4.toShort()))

    val shortRange: ClosedRange<Short> = ShortBounds((-2).toShort(), 4)
    println(shortRange.contains(3.toByte()))
    println(shortRange.contains(32768))
    println(shortRange.contains(4L))
    println(shortRange.contains(5L))

    val intRange: ClosedRange<Int> = IntBounds(2, 4)
    println(intRange.contains(3.toByte()))
    println(intRange.contains(3.toShort()))
    println(intRange.contains(4L))
    println(intRange.contains(2147483648L))

    val longRange: ClosedRange<Long> = LongBounds(2L, 4L)
    println(longRange.contains(3.toByte()))
    println(longRange.contains(3.toShort()))
    println(longRange.contains(4))

    val floatRange: ClosedRange<Float> = FloatBounds(1.0f, 2.0f)
    println(floatRange.contains(1.5))
    val doubleRange: ClosedRange<Double> = DoubleBounds(1.0, 2.0)
    println(doubleRange.contains(1.5f))
}
