@file:OptIn(ExperimentalUnsignedTypes::class)

data class Ints(val arr: IntArray)
data class Bytes(val arr: ByteArray)
data class Shorts(val arr: ShortArray)
data class Longs(val arr: LongArray)
data class Floats(val arr: FloatArray)
data class Doubles(val arr: DoubleArray)
data class Booleans(val arr: BooleanArray)
data class Chars(val arr: CharArray)
data class UBytes(val arr: UByteArray)
data class UShorts(val arr: UShortArray)
data class UInts(val arr: UIntArray)
data class ULongs(val arr: ULongArray)
data class Objects<T>(val arr: Array<T>)
data class NullableArrays(val ints: IntArray?, val doubles: DoubleArray?, val objects: Array<String?>?)
data class Mixed(val first: Int, val arr: IntArray, val last: Int)
data class Erased(val value: Any)
data class Element(val value: Int)
data class Custom(val arr: IntArray) {
    override fun hashCode(): Int = 42
}
typealias Numbers = IntArray
data class Aliased(val arr: Numbers)

fun main() {
    println(Ints(intArrayOf(1, 2)).hashCode() == Ints(intArrayOf(1, 2)).hashCode())
    println(Doubles(doubleArrayOf(1.0)).hashCode() == Doubles(doubleArrayOf(1.0)).hashCode())
    println(Ints(intArrayOf(1, 2)).hashCode())
    println(Doubles(doubleArrayOf(1.0)).hashCode())

    println(Bytes(byteArrayOf(-128, -1, 0, 127)).hashCode())
    println(Shorts(shortArrayOf(-32768, -1, 0, 32767)).hashCode())
    println(Ints(intArrayOf(Int.MIN_VALUE, -1, 0, Int.MAX_VALUE)).hashCode())
    println(Longs(longArrayOf(Long.MIN_VALUE, -1L, 0L, Long.MAX_VALUE)).hashCode())
    println(Floats(floatArrayOf(Float.NaN, -0.0f, 0.0f, Float.POSITIVE_INFINITY, -2.5f)).hashCode())
    println(Doubles(doubleArrayOf(Double.NaN, -0.0, 0.0, Double.POSITIVE_INFINITY, -2.5)).hashCode())
    println(Booleans(booleanArrayOf(true, false, true)).hashCode())
    println(Chars(charArrayOf('\u0000', 'A', '\uffff')).hashCode())
    println(UBytes(ubyteArrayOf(0u, 128u, 255u)).hashCode())
    println(UShorts(ushortArrayOf(0u, 32768u, 65535u)).hashCode())
    println(UInts(uintArrayOf(0u, 2147483648u, UInt.MAX_VALUE)).hashCode())
    println(ULongs(ulongArrayOf(0uL, 9223372036854775808uL, ULong.MAX_VALUE)).hashCode())

    println(Ints(intArrayOf()).hashCode())
    println(Doubles(doubleArrayOf()).hashCode())
    println(Objects(emptyArray<String>()).hashCode())
    println(Objects(arrayOf("a", null, "bc")).hashCode())
    println(Objects(arrayOf(1, null, 2)).hashCode())
    println(Objects(arrayOf(Element(1), Element(2))).hashCode())
    println(NullableArrays(null, null, null).hashCode())
    println(NullableArrays(intArrayOf(1, 2), null, arrayOf("a", null)).hashCode())
    println(NullableArrays(null, doubleArrayOf(1.0), null).hashCode())
    println(Mixed(7, intArrayOf(1, 2), -3).hashCode())
    println(Aliased(intArrayOf(1, 2)).hashCode())
    println(Custom(intArrayOf(1, 2)).hashCode())

    val shared = intArrayOf(1, 2)
    val holder = Ints(shared)
    println(holder == holder.copy())
    println(holder.hashCode() == holder.copy().hashCode())
    println(holder == Ints(intArrayOf(1, 2)))
    shared[0] = 9
    println(holder.hashCode())
    println(Erased(shared).hashCode() == shared.hashCode())

    // JVM data classes use shallow Arrays.hashCode, not deepHashCode.
    val nested = arrayOf(intArrayOf(1, 2), intArrayOf(3))
    println(Objects(nested).hashCode() == nested.contentHashCode())
    println(Objects(arrayOf(shared)).hashCode() == Objects(arrayOf(shared)).hashCode())
}
