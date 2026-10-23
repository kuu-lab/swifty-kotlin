@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.jvm.internal.__jvmReverseOrder
import kotlin.jvm.internal.__jvmSortList
import kotlin.jvm.internal.__jvmSortListWithComparator

private fun checkUnsignedArrayBounds(size: Int, fromIndex: Int, toIndex: Int) {
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

private fun <T : Comparable<T>> sortedUnsignedValues(
    size: Int,
    descending: Boolean,
    elementAt: (Int) -> T
): MutableList<T> {
    val result = mutableListOf<T>()
    var index = 0
    while (index < size) {
        result.add(elementAt(index))
        index++
    }
    if (descending) __jvmSortListWithComparator(result, __jvmReverseOrder()) else __jvmSortList(result)
    return result
}

private fun <T : Comparable<T>> maxOrMinUnsignedValue(
    size: Int,
    findMaximum: Boolean,
    elementAt: (Int) -> T
): T? {
    if (size == 0) return null
    var result = elementAt(0)
    var index = 1
    while (index < size) {
        val value = elementAt(index)
        val comparison = value.compareTo(result)
        if ((findMaximum && comparison > 0) || (!findMaximum && comparison < 0)) result = value
        index++
    }
    return result
}

private fun <T : Comparable<T>> binarySearchUnsignedArray(
    size: Int,
    element: T,
    fromIndex: Int,
    toIndex: Int,
    elementAt: (Int) -> T
): Int {
    checkUnsignedArrayBounds(size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val comparison = elementAt(mid).compareTo(element)
        if (comparison < 0) {
            low = mid + 1
        } else if (comparison > 0) {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

private fun <T : Comparable<T>> copySortedUnsignedValues(
    values: List<T>,
    setElement: (Int, T) -> Unit
) {
    var index = 0
    while (index < values.size) {
        setElement(index, values[index])
        index++
    }
}

public fun UIntArray.sorted(): List<UInt> = sortedUnsignedValues(size, false) { this[it] }
public fun UIntArray.sortedDescending(): List<UInt> = sortedUnsignedValues(size, true) { this[it] }
public fun UIntArray.sortedArray(): UIntArray {
    val result = UIntArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, false) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun UIntArray.sortedArrayDescending(): UIntArray {
    val result = UIntArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, true) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun UIntArray.binarySearch(element: UInt, fromIndex: Int = 0, toIndex: Int = size): Int =
    binarySearchUnsignedArray(size, element, fromIndex, toIndex) { this[it] }
public fun UIntArray.max(): UInt = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UIntArray.min(): UInt = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UIntArray.maxOrNull(): UInt? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun UIntArray.minOrNull(): UInt? = maxOrMinUnsignedValue(size, false) { this[it] }

public fun ULongArray.sorted(): List<ULong> = sortedUnsignedValues(size, false) { this[it] }
public fun ULongArray.sortedDescending(): List<ULong> = sortedUnsignedValues(size, true) { this[it] }
public fun ULongArray.sortedArray(): ULongArray {
    val result = ULongArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, false) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun ULongArray.sortedArrayDescending(): ULongArray {
    val result = ULongArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, true) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun ULongArray.binarySearch(element: ULong, fromIndex: Int = 0, toIndex: Int = size): Int =
    binarySearchUnsignedArray(size, element, fromIndex, toIndex) { this[it] }
public fun ULongArray.max(): ULong = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun ULongArray.min(): ULong = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun ULongArray.maxOrNull(): ULong? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun ULongArray.minOrNull(): ULong? = maxOrMinUnsignedValue(size, false) { this[it] }

public fun UByteArray.sorted(): List<UByte> = sortedUnsignedValues(size, false) { this[it] }
public fun UByteArray.sortedDescending(): List<UByte> = sortedUnsignedValues(size, true) { this[it] }
public fun UByteArray.sortedArray(): UByteArray {
    val result = UByteArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, false) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun UByteArray.sortedArrayDescending(): UByteArray {
    val result = UByteArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, true) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun UByteArray.binarySearch(element: UByte, fromIndex: Int = 0, toIndex: Int = size): Int =
    binarySearchUnsignedArray(size, element, fromIndex, toIndex) { this[it] }
public fun UByteArray.max(): UByte = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UByteArray.min(): UByte = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UByteArray.maxOrNull(): UByte? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun UByteArray.minOrNull(): UByte? = maxOrMinUnsignedValue(size, false) { this[it] }

public fun UShortArray.sorted(): List<UShort> = sortedUnsignedValues(size, false) { this[it] }
public fun UShortArray.sortedDescending(): List<UShort> = sortedUnsignedValues(size, true) { this[it] }
public fun UShortArray.sortedArray(): UShortArray {
    val result = UShortArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, false) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun UShortArray.sortedArrayDescending(): UShortArray {
    val result = UShortArray(size)
    copySortedUnsignedValues(sortedUnsignedValues(size, true) { this[it] }) { index, value -> result[index] = value }
    return result
}
public fun UShortArray.binarySearch(element: UShort, fromIndex: Int = 0, toIndex: Int = size): Int =
    binarySearchUnsignedArray(size, element, fromIndex, toIndex) { this[it] }
public fun UShortArray.max(): UShort = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UShortArray.min(): UShort = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UShortArray.maxOrNull(): UShort? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun UShortArray.minOrNull(): UShort? = maxOrMinUnsignedValue(size, false) { this[it] }
