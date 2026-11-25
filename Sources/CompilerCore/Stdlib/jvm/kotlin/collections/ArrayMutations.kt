@file:kotlin.jvm.JvmName("ArraysKt")

package kotlin.collections

public fun <T> Array<T>.fill(element: T, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun IntArray.fill(element: Int, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun LongArray.fill(element: Long, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun <T> Array<out T>.copyInto(destination: Array<T>, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): Array<T> {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun IntArray.copyInto(destination: IntArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): IntArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public operator fun IntArray.plus(element: Int): IntArray {
    val result = IntArray(size + 1)
    java.lang.System.arraycopy(this, 0, result, 0, size)
    result[size] = element
    return result
}

public operator fun IntArray.plus(elements: IntArray): IntArray {
    val result = IntArray(size + elements.size)
    java.lang.System.arraycopy(this, 0, result, 0, size)
    java.lang.System.arraycopy(elements, 0, result, size, elements.size)
    return result
}

public fun LongArray.copyInto(destination: LongArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): LongArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}
public fun ByteArray.fill(element: Byte, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun ByteArray.copyInto(destination: ByteArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): ByteArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun ShortArray.fill(element: Short, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun ShortArray.copyInto(destination: ShortArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): ShortArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun FloatArray.fill(element: Float, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun FloatArray.copyInto(destination: FloatArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): FloatArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun DoubleArray.fill(element: Double, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun DoubleArray.copyInto(destination: DoubleArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): DoubleArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun CharArray.fill(element: Char, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun CharArray.copyInto(destination: CharArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): CharArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun BooleanArray.fill(element: Boolean, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun BooleanArray.copyInto(destination: BooleanArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): BooleanArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

private fun checkCopyRangeEnd(toIndex: Int, size: Int) {
    if (toIndex > size) throw IndexOutOfBoundsException("toIndex ($toIndex) is greater than size ($size).")
}

public fun <T> Array<out T>.copyOfRange(fromIndex: Int, toIndex: Int): Array<T> {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange<T>(this, fromIndex, toIndex)!!
}

public fun ByteArray.copyOfRange(fromIndex: Int, toIndex: Int): ByteArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun ShortArray.copyOfRange(fromIndex: Int, toIndex: Int): ShortArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun IntArray.copyOfRange(fromIndex: Int, toIndex: Int): IntArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun LongArray.copyOfRange(fromIndex: Int, toIndex: Int): LongArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun FloatArray.copyOfRange(fromIndex: Int, toIndex: Int): FloatArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun FloatArray.slice(indices: IntRange): List<Float> {
    if (indices.isEmpty()) return emptyList()
    if (indices.endInclusive >= size) throw IndexOutOfBoundsException()
    return copyOfRange(indices.first, indices.endInclusive + 1).toList()
}

public fun DoubleArray.copyOfRange(fromIndex: Int, toIndex: Int): DoubleArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun CharArray.copyOfRange(fromIndex: Int, toIndex: Int): CharArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun BooleanArray.copyOfRange(fromIndex: Int, toIndex: Int): BooleanArray {
    checkCopyRangeEnd(toIndex, size)
    return java.util.Arrays.copyOfRange(this, fromIndex, toIndex)!!
}

public fun <T> Array<T>.sortWith(comparator: Comparator<in T>, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.sort<T>(this, fromIndex, toIndex, comparator as java.util.Comparator<T>)
}
