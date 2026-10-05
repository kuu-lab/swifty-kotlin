// contentDeep* operations must read primitive array elements by value,
// not by raw machine word (KUU-1048).
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    // Arrays.deepToString recurses into primitive arrays with value semantics.
    println(arrayOf(doubleArrayOf(1.0, 2.5, -0.5)).contentDeepToString())
    println(arrayOf(floatArrayOf(1.0f, 2.5f)).contentDeepToString())
    println(arrayOf(doubleArrayOf(-0.0, 0.0)).contentDeepToString())
    println(arrayOf(booleanArrayOf(true, false)).contentDeepToString())
    println(arrayOf(charArrayOf('a', 'z')).contentDeepToString())
    println(arrayOf(byteArrayOf(-56, 127)).contentDeepToString())
    println(arrayOf(shortArrayOf(-1, 300)).contentDeepToString())
    println(arrayOf(intArrayOf(Int.MIN_VALUE, 5)).contentDeepToString())
    println(arrayOf(longArrayOf(Long.MIN_VALUE, 5L)).contentDeepToString())
    println(arrayOf(uintArrayOf(4000000000u)).contentDeepToString())
    println(arrayOf(ubyteArrayOf(200u)).contentDeepToString())
    println(arrayOf(ushortArrayOf(60000u)).contentDeepToString())
    println(arrayOf(ulongArrayOf(ULong.MAX_VALUE, 1uL)).contentDeepToString())
    println(arrayOf(arrayOf(intArrayOf(1), intArrayOf(2, 3))).contentDeepToString())

    // Arrays.hashCode(x[]) element hashes: Double/Long fold high bits,
    // Float uses floatToIntBits, Boolean is 1231/1237.
    println(arrayOf(doubleArrayOf(1.0)).contentDeepHashCode())
    println(arrayOf(doubleArrayOf(-0.0)).contentDeepHashCode())
    println(arrayOf(doubleArrayOf(Double.NaN)).contentDeepHashCode())
    println(arrayOf(doubleArrayOf(Double.fromBits(0x7FF4000000000001L))).contentDeepHashCode())
    println(arrayOf(floatArrayOf(1.0f)).contentDeepHashCode())
    println(arrayOf(floatArrayOf(Float.NaN)).contentDeepHashCode())
    println(arrayOf(booleanArrayOf(true)).contentDeepHashCode())
    println(arrayOf(booleanArrayOf(false)).contentDeepHashCode())
    println(arrayOf(charArrayOf('a')).contentDeepHashCode())
    println(arrayOf(longArrayOf(Long.MIN_VALUE)).contentDeepHashCode())
    println(arrayOf(uintArrayOf(4000000000u)).contentDeepHashCode())
    println(arrayOf(ubyteArrayOf(200u)).contentDeepHashCode())
    println(arrayOf(ulongArrayOf(ULong.MAX_VALUE)).contentDeepHashCode())

    // Arrays.deepEquals requires the same array kind and compares floats
    // with canonical-NaN bitwise semantics (NaN == NaN, -0.0 != 0.0).
    println(arrayOf(doubleArrayOf(1.0)).contentDeepEquals(arrayOf(doubleArrayOf(1.0))))
    println(arrayOf(doubleArrayOf(-0.0)).contentDeepEquals(arrayOf(doubleArrayOf(0.0))))
    println(arrayOf(doubleArrayOf(Double.fromBits(0x7FF4000000000001L)))
        .contentDeepEquals(arrayOf(doubleArrayOf(Double.NaN))))
    println(arrayOf(floatArrayOf(Float.NaN)).contentDeepEquals(arrayOf(floatArrayOf(Float.NaN))))
    println(arrayOf(intArrayOf(1)).contentDeepEquals(arrayOf(intArrayOf(1))))
    println(arrayOf(intArrayOf(1)).contentDeepEquals(arrayOf(intArrayOf(2))))
    println(arrayOf(intArrayOf(1)).contentDeepEquals(arrayOf(longArrayOf(1L))))
    println(arrayOf(doubleArrayOf(1.0)).contentDeepEquals(arrayOf(arrayOf(1.0))))
    println(arrayOf(byteArrayOf(1)).contentDeepEquals(arrayOf(ubyteArrayOf(1u))))
    println(arrayOf(booleanArrayOf(true)).contentDeepEquals(arrayOf(booleanArrayOf(true))))
    println(arrayOf(charArrayOf('a')).contentDeepEquals(arrayOf(charArrayOf('a'))))
}
