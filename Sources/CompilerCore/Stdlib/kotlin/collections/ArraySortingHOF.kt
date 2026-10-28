@file:OptIn(ExperimentalUnsignedTypes::class)

package kotlin.collections

import kotlin.comparisons.naturalOrder
import kotlin.comparisons.reverseOrder
import kotlin.comparisons.compareValuesUnchecked

// The sorts are stable O(n log n) merge sorts (see StableSort.kt), matching
// kotlinc's `sorted*` contract.

private fun checkBinarySearchBounds(size: Int, fromIndex: Int, toIndex: Int) {
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

private fun naturalOrderUnchecked(): Comparator<Any?> =
    Comparator { a, b -> compareValuesUnchecked(a, b) }

@Suppress("UNCHECKED_CAST")
public fun <T> Array<out T>.sort() {
    (this as Array<Any?>).stableSortWith(naturalOrderUnchecked())
}

public fun <T : Comparable<T>> Array<out T>.sorted(): List<T> = sortedWith(naturalOrder<T>())

public fun <T : Comparable<T>> Array<out T>.sortedDescending(): List<T> = sortedWith(reverseOrder<T>())

public fun <T> Array<out T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val result = this.toList().toMutableList()
    result.stableSortWith(comparator)
    return result
}

public fun <T, R : Comparable<R>> Array<out T>.sortedBy(selector: (T) -> R?): List<T> {
    val result = this.toList().toMutableList()
    result.stableSortBySelector(selector, false)
    return result
}

public inline fun <T, R : Comparable<R>> Array<out T>.sortedByDescending(
    crossinline selector: (T) -> R?
): List<T> {
    val result = this.toMutableList()
    result.stableSortBySelector(selector, true)
    return result
}

@Suppress("UNCHECKED_CAST")
public inline fun <T, R : Comparable<R>> Array<out T>.sortBy(crossinline selector: (T) -> R?) {
    val result = this.toMutableList()
    result.stableSortBySelector(selector, false)
    val array = this as Array<T>
    var index = 0
    while (index < result.size) {
        array[index] = result[index]
        index += 1
    }
}

@Suppress("UNCHECKED_CAST")
public fun <T> Array<out T>.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val array = this as Array<Any?>
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortWith(naturalOrderUnchecked())
    var index = 0
    while (index < sorted.size) {
        array[fromIndex + index] = sorted[index]
        index += 1
    }
}

@Suppress("UNCHECKED_CAST")
public fun <T : Comparable<T>> Array<out T>.sortDescending() {
    (this as Array<T>).stableSortWith(reverseOrder<T>())
}

public fun <T : Comparable<T>> Array<T>.sortedArray(): Array<T> {
    return sortedArrayWith(naturalOrder<T>())
}

public fun <T : Comparable<T>> Array<T>.sortedArrayDescending(): Array<T> {
    return sortedArrayWith(reverseOrder<T>())
}

public fun <T> Array<T>.sortedArrayWith(comparator: Comparator<in T>): Array<T> {
    val result = this.copyOf()
    result.stableSortWith(comparator)
    return result
}

public fun <T> Array<T>.binarySearch(element: T, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val cmp = compareValuesUnchecked(this[mid], element)
        if (cmp < 0) {
            low = mid + 1
        } else if (cmp > 0) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun <T> Array<T>.binarySearch(
    element: T,
    comparator: Comparator<in T>,
    fromIndex: Int = 0,
    toIndex: Int = this.size
): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val cmp = comparator.compare(this[mid], element)
        if (cmp < 0) {
            low = mid + 1
        } else if (cmp > 0) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun IntArray.sorted(): List<Int> = sortedArray().toList()

public fun IntArray.sortedArray(): IntArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun IntArray.sortedArrayDescending(): IntArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun IntArray.sort() {
    this.stableSortImpl(false)
}

public fun IntArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun IntArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun IntArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun IntArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun IntArray.binarySearch(element: Int, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun LongArray.sortedArray(): LongArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun LongArray.sortedArrayDescending(): LongArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun LongArray.sort() {
    this.stableSortImpl(false)
}

public fun LongArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun LongArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun LongArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun LongArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun LongArray.binarySearch(element: Long, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun ByteArray.sortedArray(): ByteArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun ByteArray.sortedArrayDescending(): ByteArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun ByteArray.sort() {
    this.stableSortImpl(false)
}

public fun ByteArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun ByteArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun ByteArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun ByteArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun ByteArray.binarySearch(element: Byte, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun ShortArray.sortedArray(): ShortArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun ShortArray.sortedArrayDescending(): ShortArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun ShortArray.sort() {
    this.stableSortImpl(false)
}

public fun ShortArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun ShortArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun ShortArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun ShortArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun ShortArray.binarySearch(element: Short, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun CharArray.sortedArray(): CharArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun CharArray.sortedArrayDescending(): CharArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun CharArray.sort() {
    this.stableSortImpl(false)
}

public fun CharArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun CharArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun CharArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun CharArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun CharArray.binarySearch(element: Char, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun DoubleArray.sortedArray(): DoubleArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun DoubleArray.sortedArrayDescending(): DoubleArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun DoubleArray.sort() {
    this.stableSortImpl(false)
}

public fun DoubleArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun DoubleArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun DoubleArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun DoubleArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun DoubleArray.binarySearch(element: Double, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val cmp = this[mid].compareTo(element)
        if (cmp < 0) {
            low = mid + 1
        } else if (cmp > 0) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun FloatArray.sortedArray(): FloatArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun FloatArray.sortedArrayDescending(): FloatArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun FloatArray.sort() {
    this.stableSortImpl(false)
}

public fun FloatArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun FloatArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun FloatArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun FloatArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun FloatArray.binarySearch(element: Float, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val cmp = this[mid].compareTo(element)
        if (cmp < 0) {
            low = mid + 1
        } else if (cmp > 0) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun UByteArray.sorted(): List<UByte> = sortedArray().toList()

public fun UByteArray.sortedArray(): UByteArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun UByteArray.sortedArrayDescending(): UByteArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun UByteArray.sort() {
    this.stableSortImpl(false)
}

public fun UByteArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun UByteArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun UByteArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun UByteArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun UByteArray.binarySearch(element: UByte, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun UShortArray.sorted(): List<UShort> = sortedArray().toList()

public fun UShortArray.sortedArray(): UShortArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun UShortArray.sortedArrayDescending(): UShortArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun UShortArray.sort() {
    this.stableSortImpl(false)
}

public fun UShortArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun UShortArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun UShortArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun UShortArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun UShortArray.binarySearch(element: UShort, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun UIntArray.sorted(): List<UInt> = sortedArray().toList()

public fun UIntArray.sortedArray(): UIntArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun UIntArray.sortedArrayDescending(): UIntArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun UIntArray.sort() {
    this.stableSortImpl(false)
}

public fun UIntArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun UIntArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun UIntArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun UIntArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun UIntArray.binarySearch(element: UInt, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun ULongArray.sorted(): List<ULong> = sortedArray().toList()

public fun ULongArray.sortedArray(): ULongArray {
    val result = this.copyOf()
    result.stableSortImpl(false)
    return result
}

public fun ULongArray.sortedArrayDescending(): ULongArray {
    val result = this.copyOf()
    result.stableSortImpl(true)
    return result
}

public fun ULongArray.sort() {
    this.stableSortImpl(false)
}

public fun ULongArray.sort(fromIndex: Int = 0, toIndex: Int = this.size) {
    this.sortRange(fromIndex, toIndex, false)
}

public fun ULongArray.sortDescending() {
    this.stableSortImpl(true)
}

public fun ULongArray.sortDescending(fromIndex: Int, toIndex: Int) {
    this.sortRange(fromIndex, toIndex, true)
}

private fun ULongArray.sortRange(fromIndex: Int, toIndex: Int, descending: Boolean) {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    if (toIndex - fromIndex <= 1) return
    val sorted = this.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(descending)
    var index = 0
    while (index < sorted.size) {
        this[fromIndex + index] = sorted[index]
        index += 1
    }
}

public fun ULongArray.binarySearch(element: ULong, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val midVal = this[mid]
        if (midVal < element) {
            low = mid + 1
        } else if (midVal > element) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

public fun IntArray.sortedDescending(): List<Int> = sortedArrayDescending().toList()

public fun LongArray.sortedDescending(): List<Long> = sortedArrayDescending().toList()

public fun ShortArray.sortedDescending(): List<Short> = sortedArrayDescending().toList()

public fun ByteArray.sortedDescending(): List<Byte> = sortedArrayDescending().toList()

public fun CharArray.sortedDescending(): List<Char> = sortedArrayDescending().toList()

public fun DoubleArray.sortedDescending(): List<Double> = sortedArrayDescending().toList()

public fun FloatArray.sortedDescending(): List<Float> = sortedArrayDescending().toList()

public fun UByteArray.sortedDescending(): List<UByte> = sortedArrayDescending().toList()

public fun UShortArray.sortedDescending(): List<UShort> = sortedArrayDescending().toList()

public fun UIntArray.sortedDescending(): List<UInt> = sortedArrayDescending().toList()

public fun ULongArray.sortedDescending(): List<ULong> = sortedArrayDescending().toList()
