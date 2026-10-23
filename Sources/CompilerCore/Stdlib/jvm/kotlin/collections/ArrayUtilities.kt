@file:kotlin.jvm.JvmName("ArraysKt")

package kotlin.collections

public infix fun <T> Array<out T>?.contentEquals(other: Array<out T>?): Boolean =
    java.util.Arrays.equals(this, other)

public fun <T> Array<out T>?.contentHashCode(): Int = java.util.Arrays.hashCode(this)

public fun <T> Array<out T>?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun <T> Array<out T>?.contentDeepEquals(other: Array<out T>?): Boolean =
    java.util.Arrays.deepEquals(this, other)

public fun <T> Array<out T>?.contentDeepHashCode(): Int = java.util.Arrays.deepHashCode(this)

public fun <T> Array<out T>?.contentDeepToString(): String = java.util.Arrays.deepToString(this)

public infix fun ByteArray?.contentEquals(other: ByteArray?): Boolean = java.util.Arrays.equals(this, other)
public fun ByteArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun ByteArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun ShortArray?.contentEquals(other: ShortArray?): Boolean = java.util.Arrays.equals(this, other)
public fun ShortArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun ShortArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun IntArray?.contentEquals(other: IntArray?): Boolean = java.util.Arrays.equals(this, other)
public fun IntArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun IntArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun LongArray?.contentEquals(other: LongArray?): Boolean = java.util.Arrays.equals(this, other)
public fun LongArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun LongArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun FloatArray?.contentEquals(other: FloatArray?): Boolean = java.util.Arrays.equals(this, other)
public fun FloatArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun FloatArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun DoubleArray?.contentEquals(other: DoubleArray?): Boolean = java.util.Arrays.equals(this, other)
public fun DoubleArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun DoubleArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun BooleanArray?.contentEquals(other: BooleanArray?): Boolean = java.util.Arrays.equals(this, other)
public fun BooleanArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun BooleanArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun CharArray?.contentEquals(other: CharArray?): Boolean = java.util.Arrays.equals(this, other)
public fun CharArray?.contentHashCode(): Int = java.util.Arrays.hashCode(this)
public fun CharArray?.contentToString(): String = java.util.Arrays.toString(this)

public infix fun UByteArray?.contentEquals(other: UByteArray?): Boolean {
    if (this == null) return other == null
    if (other == null || size != other.size) return false
    var index = 0
    while (index < size) {
        if (this[index] != other[index]) return false
        index++
    }
    return true
}

public fun UByteArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var index = 0
    while (index < size) {
        result = 31 * result + this[index].hashCode()
        index++
    }
    return result
}

public fun UByteArray?.contentToString(): String {
    if (this == null) return "null"
    val result = StringBuilder("[")
    var index = 0
    while (index < size) {
        if (index > 0) result.append(", ")
        result.append(this[index].toString())
        index++
    }
    result.append("]")
    return result.toString()
}

public infix fun UShortArray?.contentEquals(other: UShortArray?): Boolean {
    if (this == null) return other == null
    if (other == null || size != other.size) return false
    var index = 0
    while (index < size) {
        if (this[index] != other[index]) return false
        index++
    }
    return true
}

public fun UShortArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var index = 0
    while (index < size) {
        result = 31 * result + this[index].hashCode()
        index++
    }
    return result
}

public fun UShortArray?.contentToString(): String {
    if (this == null) return "null"
    val result = StringBuilder("[")
    var index = 0
    while (index < size) {
        if (index > 0) result.append(", ")
        result.append(this[index].toString())
        index++
    }
    result.append("]")
    return result.toString()
}

public infix fun UIntArray?.contentEquals(other: UIntArray?): Boolean {
    if (this == null) return other == null
    if (other == null || size != other.size) return false
    var index = 0
    while (index < size) {
        if (this[index] != other[index]) return false
        index++
    }
    return true
}

public fun UIntArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var index = 0
    while (index < size) {
        result = 31 * result + this[index].hashCode()
        index++
    }
    return result
}

public fun UIntArray?.contentToString(): String {
    if (this == null) return "null"
    val result = StringBuilder("[")
    var index = 0
    while (index < size) {
        if (index > 0) result.append(", ")
        result.append(this[index].toString())
        index++
    }
    result.append("]")
    return result.toString()
}

public infix fun ULongArray?.contentEquals(other: ULongArray?): Boolean {
    if (this == null) return other == null
    if (other == null || size != other.size) return false
    var index = 0
    while (index < size) {
        if (this[index] != other[index]) return false
        index++
    }
    return true
}

public fun ULongArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var index = 0
    while (index < size) {
        result = 31 * result + this[index].hashCode()
        index++
    }
    return result
}

public fun ULongArray?.contentToString(): String {
    if (this == null) return "null"
    val result = StringBuilder("[")
    var index = 0
    while (index < size) {
        if (index > 0) result.append(", ")
        result.append(this[index].toString())
        index++
    }
    result.append("]")
    return result.toString()
}

public fun <T> Array<T>.reversedArray(): Array<T> {
    @Suppress("UNCHECKED_CAST")
    val result = java.util.Arrays.copyOf(this, size) as Array<T>
    result.reverseInPlace(0, result.size)
    return result
}

private fun <T> Array<T>.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

private fun checkArrayBinarySearchBounds(size: Int, fromIndex: Int, toIndex: Int) {
    if (fromIndex > toIndex) {
        throw IllegalArgumentException("fromIndex ($fromIndex) is greater than toIndex ($toIndex).")
    }
    if (fromIndex < 0) {
        throw IndexOutOfBoundsException("fromIndex ($fromIndex) is less than zero.")
    }
    if (toIndex > size) {
        throw IndexOutOfBoundsException("toIndex ($toIndex) is greater than size ($size).")
    }
}

@Suppress("UNCHECKED_CAST")
private fun <T> Array<T>.arrayUtilityStableSortWith(comparator: Comparator<in T>) {
    if (size < 2) return
    var source = java.util.Arrays.copyOf(this, size) as Array<T>
    var destination: Array<T> = this
    var width = 1
    while (width < size) {
        var start = 0
        while (start < size) {
            val middle = if (width > size - start) size else start + width
            val end = if (width > size - middle) size else middle + width
            var left = start
            var right = middle
            var output = start
            while (left < middle && right < end) {
                if (comparator.compare(source[left], source[right]) <= 0) {
                    destination[output] = source[left]
                    left++
                } else {
                    destination[output] = source[right]
                    right++
                }
                output++
            }
            while (left < middle) {
                destination[output] = source[left]
                left++
                output++
            }
            while (right < end) {
                destination[output] = source[right]
                right++
                output++
            }
            start = end
        }
        val previousSource = source
        source = destination
        destination = previousSource
        width = if (width > size / 2) size else width * 2
    }
    if (source !== this) {
        var index = 0
        while (index < size) {
            this[index] = source[index]
            index++
        }
    }
}

public fun <T> Array<out T>.sort(): Unit = java.util.Arrays.sort(this)

public fun <T> Array<out T>.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun <T : Comparable<T>> Array<out T>.sortDescending(): Unit {
    @Suppress("UNCHECKED_CAST")
    val array = this as Array<T>
    array.arrayUtilityStableSortWith(Comparator<T> { first, second -> second.compareTo(first) })
}

public fun <T> Array<T>.sortWith(comparator: Comparator<in T>): Unit {
    arrayUtilityStableSortWith(comparator)
}

public fun <T : Comparable<T>> Array<T>.sortedArray(): Array<T> {
    @Suppress("UNCHECKED_CAST")
    val result = java.util.Arrays.copyOf(this, size) as Array<T>
    java.util.Arrays.sort(result)
    return result
}

public fun <T : Comparable<T>> Array<T>.sortedArrayDescending(): Array<T> {
    @Suppress("UNCHECKED_CAST")
    val result = java.util.Arrays.copyOf(this, size) as Array<T>
    result.arrayUtilityStableSortWith(Comparator<T> { first, second -> second.compareTo(first) })
    return result
}

public fun <T> Array<T>.sortedArrayWith(comparator: Comparator<in T>): Array<T> {
    @Suppress("UNCHECKED_CAST")
    val result = java.util.Arrays.copyOf(this, size) as Array<T>
    result.arrayUtilityStableSortWith(comparator)
    return result
}

public fun <T> Array<out T>.binarySearch(element: T, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun <T> Array<out T>.binarySearch(
    element: T,
    comparator: Comparator<in T>,
    fromIndex: Int = 0,
    toIndex: Int = size
): Int {
    checkArrayBinarySearchBounds(size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val middle = (low + high) ushr 1
        val comparison = comparator.compare(this[middle], element)
        if (comparison < 0) low = middle + 1
        else if (comparison > 0) high = middle - 1
        else return middle
    }
    return -(low + 1)
}

public fun ByteArray.reversedArray(): ByteArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun ByteArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun ByteArray.sort(): Unit = java.util.Arrays.sort(this)

public fun ByteArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun ByteArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun ByteArray.sortedArray(): ByteArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun ByteArray.sortedArrayDescending(): ByteArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun ByteArray.binarySearch(element: Byte, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun ShortArray.reversedArray(): ShortArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun ShortArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun ShortArray.sort(): Unit = java.util.Arrays.sort(this)

public fun ShortArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun ShortArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun ShortArray.sortedArray(): ShortArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun ShortArray.sortedArrayDescending(): ShortArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun ShortArray.binarySearch(element: Short, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun IntArray.reversedArray(): IntArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun IntArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun IntArray.sort(): Unit = java.util.Arrays.sort(this)

public fun IntArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun IntArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun IntArray.sortedArray(): IntArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun IntArray.sortedArrayDescending(): IntArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun IntArray.binarySearch(element: Int, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun LongArray.reversedArray(): LongArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun LongArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun LongArray.sort(): Unit = java.util.Arrays.sort(this)

public fun LongArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun LongArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun LongArray.sortedArray(): LongArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun LongArray.sortedArrayDescending(): LongArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun LongArray.binarySearch(element: Long, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun FloatArray.reversedArray(): FloatArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun FloatArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun FloatArray.sort(): Unit = java.util.Arrays.sort(this)

public fun FloatArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun FloatArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun FloatArray.sortedArray(): FloatArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun FloatArray.sortedArrayDescending(): FloatArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun FloatArray.binarySearch(element: Float, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun DoubleArray.reversedArray(): DoubleArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun DoubleArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun DoubleArray.sort(): Unit = java.util.Arrays.sort(this)

public fun DoubleArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun DoubleArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun DoubleArray.sortedArray(): DoubleArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun DoubleArray.sortedArrayDescending(): DoubleArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun DoubleArray.binarySearch(element: Double, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

public fun BooleanArray.reversedArray(): BooleanArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun BooleanArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun CharArray.reversedArray(): CharArray {
    val result = java.util.Arrays.copyOf(this, size)
    result.reverseInPlace(0, result.size)
    return result
}

private fun CharArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

public fun CharArray.sort(): Unit = java.util.Arrays.sort(this)

public fun CharArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    java.util.Arrays.sort(this, fromIndex, toIndex)

public fun CharArray.sortDescending(): Unit {
    sort()
    reverseInPlace(0, size)
}

public fun CharArray.sortedArray(): CharArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    return result
}

public fun CharArray.sortedArrayDescending(): CharArray {
    val result = java.util.Arrays.copyOf(this, size)
    java.util.Arrays.sort(result)
    result.reverseInPlace(0, result.size)
    return result
}

public fun CharArray.binarySearch(element: Char, fromIndex: Int = 0, toIndex: Int = size): Int =
    java.util.Arrays.binarySearch(this, fromIndex, toIndex, element)

private fun checkArrayUtilityRange(size: Int, fromIndex: Int, toIndex: Int) {
    if (fromIndex > toIndex) {
        throw IllegalArgumentException("fromIndex ($fromIndex) is greater than toIndex ($toIndex).")
    }
    if (fromIndex < 0 || toIndex > size) {
        throw IndexOutOfBoundsException("Array range ($fromIndex, $toIndex) is out of bounds for size $size.")
    }
}

private inline fun arrayUtilityHeapSort(
    size: Int,
    compare: (Int, Int) -> Int,
    swap: (Int, Int) -> Unit
) {
    var start = size / 2 - 1
    while (start >= 0) {
        arrayUtilitySiftDown(start, size, compare, swap)
        start--
    }
    var end = size - 1
    while (end > 0) {
        swap(0, end)
        arrayUtilitySiftDown(0, end, compare, swap)
        end--
    }
}

private inline fun arrayUtilitySiftDown(
    root: Int,
    end: Int,
    compare: (Int, Int) -> Int,
    swap: (Int, Int) -> Unit
) {
    var parent = root
    while (parent * 2 + 1 < end) {
        var child = parent * 2 + 1
        if (child + 1 < end && compare(child, child + 1) < 0) child++
        if (compare(parent, child) >= 0) return
        swap(parent, child)
        parent = child
    }
}

public fun UByteArray.reversedArray(): UByteArray {
    val result = UByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[size - index - 1]
        index++
    }
    return result
}

private fun UByteArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

private fun UByteArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    arrayUtilityHeapSort(
        toIndex - fromIndex,
        { first, second ->
            if (descending) this[fromIndex + second].compareTo(this[fromIndex + first])
            else this[fromIndex + first].compareTo(this[fromIndex + second])
        },
        { first, second ->
            val value = this[fromIndex + first]
            this[fromIndex + first] = this[fromIndex + second]
            this[fromIndex + second] = value
        }
    )
}

public fun UByteArray.sort(): Unit = sortRange(0, size, false)

public fun UByteArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    sortRange(fromIndex, toIndex, false)

public fun UByteArray.sortDescending(): Unit = sortRange(0, size, true)

public fun UByteArray.sortedArray(): UByteArray {
    val result = UByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sort()
    return result
}

public fun UByteArray.sortedArrayDescending(): UByteArray {
    val result = UByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sortDescending()
    return result
}

public fun UByteArray.binarySearch(element: UByte, fromIndex: Int = 0, toIndex: Int = size): Int {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val comparison = this[mid].compareTo(element)
        if (comparison < 0) low = mid + 1
        else if (comparison > 0) high = mid - 1
        else return mid
    }
    return -(low + 1)
}

public fun UShortArray.reversedArray(): UShortArray {
    val result = UShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[size - index - 1]
        index++
    }
    return result
}

private fun UShortArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

private fun UShortArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    arrayUtilityHeapSort(
        toIndex - fromIndex,
        { first, second ->
            if (descending) this[fromIndex + second].compareTo(this[fromIndex + first])
            else this[fromIndex + first].compareTo(this[fromIndex + second])
        },
        { first, second ->
            val value = this[fromIndex + first]
            this[fromIndex + first] = this[fromIndex + second]
            this[fromIndex + second] = value
        }
    )
}

public fun UShortArray.sort(): Unit = sortRange(0, size, false)

public fun UShortArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    sortRange(fromIndex, toIndex, false)

public fun UShortArray.sortDescending(): Unit = sortRange(0, size, true)

public fun UShortArray.sortedArray(): UShortArray {
    val result = UShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sort()
    return result
}

public fun UShortArray.sortedArrayDescending(): UShortArray {
    val result = UShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sortDescending()
    return result
}

public fun UShortArray.binarySearch(element: UShort, fromIndex: Int = 0, toIndex: Int = size): Int {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val comparison = this[mid].compareTo(element)
        if (comparison < 0) low = mid + 1
        else if (comparison > 0) high = mid - 1
        else return mid
    }
    return -(low + 1)
}

public fun UIntArray.reversedArray(): UIntArray {
    val result = UIntArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[size - index - 1]
        index++
    }
    return result
}

private fun UIntArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

private fun UIntArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    arrayUtilityHeapSort(
        toIndex - fromIndex,
        { first, second ->
            if (descending) this[fromIndex + second].compareTo(this[fromIndex + first])
            else this[fromIndex + first].compareTo(this[fromIndex + second])
        },
        { first, second ->
            val value = this[fromIndex + first]
            this[fromIndex + first] = this[fromIndex + second]
            this[fromIndex + second] = value
        }
    )
}

public fun UIntArray.sort(): Unit = sortRange(0, size, false)

public fun UIntArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    sortRange(fromIndex, toIndex, false)

public fun UIntArray.sortDescending(): Unit = sortRange(0, size, true)

public fun UIntArray.sortedArray(): UIntArray {
    val result = UIntArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sort()
    return result
}

public fun UIntArray.sortedArrayDescending(): UIntArray {
    val result = UIntArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sortDescending()
    return result
}

public fun UIntArray.binarySearch(element: UInt, fromIndex: Int = 0, toIndex: Int = size): Int {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val comparison = this[mid].compareTo(element)
        if (comparison < 0) low = mid + 1
        else if (comparison > 0) high = mid - 1
        else return mid
    }
    return -(low + 1)
}

public fun ULongArray.reversedArray(): ULongArray {
    val result = ULongArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[size - index - 1]
        index++
    }
    return result
}

private fun ULongArray.reverseInPlace(fromIndex: Int, toIndex: Int) {
    var left = fromIndex
    var right = toIndex - 1
    while (left < right) {
        val value = this[left]
        this[left] = this[right]
        this[right] = value
        left++
        right--
    }
}

private fun ULongArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    arrayUtilityHeapSort(
        toIndex - fromIndex,
        { first, second ->
            if (descending) this[fromIndex + second].compareTo(this[fromIndex + first])
            else this[fromIndex + first].compareTo(this[fromIndex + second])
        },
        { first, second ->
            val value = this[fromIndex + first]
            this[fromIndex + first] = this[fromIndex + second]
            this[fromIndex + second] = value
        }
    )
}

public fun ULongArray.sort(): Unit = sortRange(0, size, false)

public fun ULongArray.sort(fromIndex: Int = 0, toIndex: Int = size): Unit =
    sortRange(fromIndex, toIndex, false)

public fun ULongArray.sortDescending(): Unit = sortRange(0, size, true)

public fun ULongArray.sortedArray(): ULongArray {
    val result = ULongArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sort()
    return result
}

public fun ULongArray.sortedArrayDescending(): ULongArray {
    val result = ULongArray(size)
    var index = 0
    while (index < size) {
        result[index] = this[index]
        index++
    }
    result.sortDescending()
    return result
}

public fun ULongArray.binarySearch(element: ULong, fromIndex: Int = 0, toIndex: Int = size): Int {
    checkArrayUtilityRange(size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val comparison = this[mid].compareTo(element)
        if (comparison < 0) low = mid + 1
        else if (comparison > 0) high = mid - 1
        else return mid
    }
    return -(low + 1)
}
