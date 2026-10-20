package kotlin
class Array<T> { val size: Int get() = 0; operator fun get(index: Int): T = null!!; operator fun set(index: Int, value: T) {} }
inline fun <reified T> arrayOf(vararg elements: T): Array<T> = null!!
inline fun <reified T> arrayOfNulls(size: Int): Array<T?> = null!!
inline fun <reified T> emptyArray(): Array<T> = null!!
class IntArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Int = null!!; operator fun set(index: Int, value: Int) {} }
fun intArrayOf(vararg elements: Int): IntArray = null!!
class LongArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Long = null!!; operator fun set(index: Int, value: Long) {} }
fun longArrayOf(vararg elements: Long): LongArray = null!!
class FloatArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Float = null!!; operator fun set(index: Int, value: Float) {} }
fun floatArrayOf(vararg elements: Float): FloatArray = null!!
class DoubleArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Double = null!!; operator fun set(index: Int, value: Double) {} }
fun doubleArrayOf(vararg elements: Double): DoubleArray = null!!
class BooleanArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Boolean = null!!; operator fun set(index: Int, value: Boolean) {} }
fun booleanArrayOf(vararg elements: Boolean): BooleanArray = null!!
class CharArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Char = null!!; operator fun set(index: Int, value: Char) {} }
fun charArrayOf(vararg elements: Char): CharArray = null!!
class ByteArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Byte = null!!; operator fun set(index: Int, value: Byte) {} }
fun byteArrayOf(vararg elements: Byte): ByteArray = null!!
class ShortArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): Short = null!!; operator fun set(index: Int, value: Short) {} }
fun shortArrayOf(vararg elements: Short): ShortArray = null!!
class UIntArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): UInt = null!!; operator fun set(index: Int, value: UInt) {} }
fun uintArrayOf(vararg elements: UInt): UIntArray = null!!
class ULongArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): ULong = null!!; operator fun set(index: Int, value: ULong) {} }
fun ulongArrayOf(vararg elements: ULong): ULongArray = null!!
class UByteArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): UByte = null!!; operator fun set(index: Int, value: UByte) {} }
fun ubyteArrayOf(vararg elements: UByte): UByteArray = null!!
class UShortArray(size: Int) { val size: Int get() = 0; operator fun get(index: Int): UShort = null!!; operator fun set(index: Int, value: UShort) {} }
fun ushortArrayOf(vararg elements: UShort): UShortArray = null!!
