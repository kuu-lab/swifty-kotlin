@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.jvm.internal.__jvmReverseOrder
import kotlin.jvm.internal.__jvmSortList
import kotlin.jvm.internal.__jvmSortListWithComparator

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

public fun UIntArray.sorted(): List<UInt> = sortedUnsignedValues(size, false) { this[it] }
public fun UIntArray.sortedDescending(): List<UInt> = sortedUnsignedValues(size, true) { this[it] }
public fun UIntArray.max(): UInt = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UIntArray.min(): UInt = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UIntArray.maxOrNull(): UInt? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun UIntArray.minOrNull(): UInt? = maxOrMinUnsignedValue(size, false) { this[it] }

public fun ULongArray.sorted(): List<ULong> = sortedUnsignedValues(size, false) { this[it] }
public fun ULongArray.sortedDescending(): List<ULong> = sortedUnsignedValues(size, true) { this[it] }
public fun ULongArray.max(): ULong = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun ULongArray.min(): ULong = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun ULongArray.maxOrNull(): ULong? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun ULongArray.minOrNull(): ULong? = maxOrMinUnsignedValue(size, false) { this[it] }

public fun UByteArray.sorted(): List<UByte> = sortedUnsignedValues(size, false) { this[it] }
public fun UByteArray.sortedDescending(): List<UByte> = sortedUnsignedValues(size, true) { this[it] }
public fun UByteArray.max(): UByte = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UByteArray.min(): UByte = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UByteArray.maxOrNull(): UByte? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun UByteArray.minOrNull(): UByte? = maxOrMinUnsignedValue(size, false) { this[it] }

public fun UShortArray.sorted(): List<UShort> = sortedUnsignedValues(size, false) { this[it] }
public fun UShortArray.sortedDescending(): List<UShort> = sortedUnsignedValues(size, true) { this[it] }
public fun UShortArray.max(): UShort = maxOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UShortArray.min(): UShort = minOrNull() ?: throw NoSuchElementException("Array is empty.")
public fun UShortArray.maxOrNull(): UShort? = maxOrMinUnsignedValue(size, true) { this[it] }
public fun UShortArray.minOrNull(): UShort? = maxOrMinUnsignedValue(size, false) { this[it] }
