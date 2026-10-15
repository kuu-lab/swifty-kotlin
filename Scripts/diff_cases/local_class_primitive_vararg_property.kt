// KUU-2144: local constructor properties must expose their packed array type.
// KOTLINC_FLAGS: -Xjdk-release=17
@file:OptIn(ExperimentalUnsignedTypes::class)

typealias Count = Int
typealias Tag = ULong

fun main() {
    class BooleanHolder(vararg val values: Boolean) {
        val initialSize: Int = values.size
        fun read(): BooleanArray = values
    }
    val booleanValues: BooleanArray = BooleanHolder(true, false).read()
    println(booleanValues[0])
    println(booleanValues[1])
    println(BooleanHolder().values.size)
    println(BooleanHolder(*booleanArrayOf(true, false)).initialSize)
    class ByteHolder(vararg val values: Byte) {
        val initialSize: Int = values.size
        fun read(): ByteArray = values
    }
    val byteValues: ByteArray = ByteHolder(1.toByte(), 2.toByte()).read()
    println(byteValues[0])
    println(byteValues[1])
    println(ByteHolder().values.size)
    println(ByteHolder(*byteArrayOf(1.toByte(), 2.toByte())).initialSize)
    class ShortHolder(vararg val values: Short) {
        val initialSize: Int = values.size
        fun read(): ShortArray = values
    }
    val shortValues: ShortArray = ShortHolder(1.toShort(), 2.toShort()).read()
    println(shortValues[0])
    println(shortValues[1])
    println(ShortHolder().values.size)
    println(ShortHolder(*shortArrayOf(1.toShort(), 2.toShort())).initialSize)
    class IntHolder(vararg val values: Int) {
        val initialSize: Int = values.size
        fun read(): IntArray = values
    }
    val intValues: IntArray = IntHolder(1, 2).read()
    println(intValues[0])
    println(intValues[1])
    println(IntHolder().values.size)
    println(IntHolder(*intArrayOf(1, 2)).initialSize)
    class LongHolder(vararg val values: Long) {
        val initialSize: Int = values.size
        fun read(): LongArray = values
    }
    val longValues: LongArray = LongHolder(1L, 2L).read()
    println(longValues[0])
    println(longValues[1])
    println(LongHolder().values.size)
    println(LongHolder(*longArrayOf(1L, 2L)).initialSize)
    class CharHolder(vararg val values: Char) {
        val initialSize: Int = values.size
        fun read(): CharArray = values
    }
    val charValues: CharArray = CharHolder('a', 'b').read()
    println(charValues[0])
    println(charValues[1])
    println(CharHolder().values.size)
    println(CharHolder(*charArrayOf('a', 'b')).initialSize)
    class FloatHolder(vararg val values: Float) {
        val initialSize: Int = values.size
        fun read(): FloatArray = values
    }
    val floatValues: FloatArray = FloatHolder(1.5f, 2.5f).read()
    println(floatValues[0])
    println(floatValues[1])
    println(FloatHolder().values.size)
    println(FloatHolder(*floatArrayOf(1.5f, 2.5f)).initialSize)
    class DoubleHolder(vararg val values: Double) {
        val initialSize: Int = values.size
        fun read(): DoubleArray = values
    }
    val doubleValues: DoubleArray = DoubleHolder(1.5, 2.5).read()
    println(doubleValues[0])
    println(doubleValues[1])
    println(DoubleHolder().values.size)
    println(DoubleHolder(*doubleArrayOf(1.5, 2.5)).initialSize)
    class UByteHolder(vararg val values: UByte) {
        val initialSize: Int = values.size
        fun read(): UByteArray = values
    }
    val uByteValues: UByteArray = UByteHolder(1u.toUByte(), 2u.toUByte()).read()
    println(uByteValues[0])
    println(uByteValues[1])
    println(UByteHolder().values.size)
    println(UByteHolder(*ubyteArrayOf(1u.toUByte(), 2u.toUByte())).initialSize)
    class UShortHolder(vararg val values: UShort) {
        val initialSize: Int = values.size
        fun read(): UShortArray = values
    }
    val uShortValues: UShortArray = UShortHolder(1u.toUShort(), 2u.toUShort()).read()
    println(uShortValues[0])
    println(uShortValues[1])
    println(UShortHolder().values.size)
    println(UShortHolder(*ushortArrayOf(1u.toUShort(), 2u.toUShort())).initialSize)
    class UIntHolder(vararg val values: UInt) {
        val initialSize: Int = values.size
        fun read(): UIntArray = values
    }
    val uIntValues: UIntArray = UIntHolder(1u, 2u).read()
    println(uIntValues[0])
    println(uIntValues[1])
    println(UIntHolder().values.size)
    println(UIntHolder(*uintArrayOf(1u, 2u)).initialSize)
    class ULongHolder(vararg val values: ULong) {
        val initialSize: Int = values.size
        fun read(): ULongArray = values
    }
    val uLongValues: ULongArray = ULongHolder(1uL, 2uL).read()
    println(uLongValues[0])
    println(uLongValues[1])
    println(ULongHolder().values.size)
    println(ULongHolder(*ulongArrayOf(1uL, 2uL)).initialSize)
    class Aliased(vararg var counts: Count) { fun read(): IntArray = counts }
    val aliased = Aliased(3, 4)
    aliased.counts = intArrayOf(5)
    println(aliased.read()[0])
    class UnsignedAlias(vararg val tags: Tag)
    val tags: ULongArray = UnsignedAlias(7uL).tags
    println(tags[0])
    class References(vararg val words: String)
    val words: Array<out String> = References("x", "y").words
    println(words[1])
    class Nullable(vararg val numbers: Int?)
    val numbers: Array<out Int?> = Nullable(null, 9).numbers
    println(numbers[0])
    println(numbers[1])
}
