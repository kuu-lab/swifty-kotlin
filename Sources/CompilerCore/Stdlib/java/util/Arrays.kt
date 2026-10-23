package java.util

import kotlin.collections.asList
import kotlin.collections.binarySearch
import kotlin.collections.contentDeepEquals
import kotlin.collections.contentDeepHashCode
import kotlin.collections.contentDeepToString
import kotlin.collections.contentEquals
import kotlin.collections.contentHashCode
import kotlin.collections.contentToString
import kotlin.collections.copyOf
import kotlin.collections.copyOfRange
import kotlin.collections.fill
import kotlin.collections.sort
import kotlin.collections.stableSortImpl
import kotlin.internal.__valuesEqual

public object Arrays {
    public fun <T> asList(vararg elements: T): List<T> = elements.asList()

    public fun equals(first: Array<out Any?>?, second: Array<out Any?>?): Boolean =
        first.contentEquals(second)

    public fun equals(first: BooleanArray?, second: BooleanArray?): Boolean = first.contentEquals(second)
    public fun equals(first: ByteArray?, second: ByteArray?): Boolean = first.contentEquals(second)
    public fun equals(first: ShortArray?, second: ShortArray?): Boolean = first.contentEquals(second)
    public fun equals(first: CharArray?, second: CharArray?): Boolean = first.contentEquals(second)
    public fun equals(first: IntArray?, second: IntArray?): Boolean = first.contentEquals(second)
    public fun equals(first: LongArray?, second: LongArray?): Boolean = first.contentEquals(second)
    public fun equals(first: FloatArray?, second: FloatArray?): Boolean = first.contentEquals(second)
    public fun equals(first: DoubleArray?, second: DoubleArray?): Boolean = first.contentEquals(second)

    public fun deepEquals(first: Array<out Any?>?, second: Array<out Any?>?): Boolean =
        first.contentDeepEquals(second)

    public fun hashCode(array: Array<out Any?>?): Int = array.contentHashCode()
    public fun hashCode(array: BooleanArray?): Int = array.contentHashCode()
    public fun hashCode(array: ByteArray?): Int = array.contentHashCode()
    public fun hashCode(array: ShortArray?): Int = array.contentHashCode()
    public fun hashCode(array: CharArray?): Int = array.contentHashCode()
    public fun hashCode(array: IntArray?): Int = array.contentHashCode()
    public fun hashCode(array: LongArray?): Int = array.contentHashCode()
    public fun hashCode(array: FloatArray?): Int = array.contentHashCode()
    public fun hashCode(array: DoubleArray?): Int = array.contentHashCode()

    public fun deepHashCode(array: Array<out Any?>?): Int = array.contentDeepHashCode()

    public fun toString(array: Array<out Any?>?): String = array.contentToString()
    public fun toString(array: BooleanArray?): String = array.contentToString()
    public fun toString(array: ByteArray?): String = array.contentToString()
    public fun toString(array: ShortArray?): String = array.contentToString()
    public fun toString(array: CharArray?): String = array.contentToString()
    public fun toString(array: IntArray?): String = array.contentToString()
    public fun toString(array: LongArray?): String = array.contentToString()
    public fun toString(array: FloatArray?): String = array.contentToString()
    public fun toString(array: DoubleArray?): String = array.contentToString()

    public fun deepToString(array: Array<out Any?>?): String = array.contentDeepToString()

    public fun <T> fill(array: Array<T>?, value: T) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun <T> fill(array: Array<T>?, fromIndex: Int, toIndex: Int, value: T) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: BooleanArray?, value: Boolean) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: BooleanArray?, fromIndex: Int, toIndex: Int, value: Boolean) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: ByteArray?, value: Byte) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: ByteArray?, fromIndex: Int, toIndex: Int, value: Byte) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: ShortArray?, value: Short) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: ShortArray?, fromIndex: Int, toIndex: Int, value: Short) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: CharArray?, value: Char) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: CharArray?, fromIndex: Int, toIndex: Int, value: Char) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: IntArray?, value: Int) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: IntArray?, fromIndex: Int, toIndex: Int, value: Int) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: LongArray?, value: Long) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: LongArray?, fromIndex: Int, toIndex: Int, value: Long) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: FloatArray?, value: Float) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: FloatArray?, fromIndex: Int, toIndex: Int, value: Float) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun fill(array: DoubleArray?, value: Double) {
        (array ?: throw NullPointerException()).fill(value)
    }

    public fun fill(array: DoubleArray?, fromIndex: Int, toIndex: Int, value: Double) {
        (array ?: throw NullPointerException()).fill(value, fromIndex, toIndex)
    }

    public fun <T> binarySearch(
        array: Array<T>?, value: T, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0
    ): Int = (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)

    public fun <T> binarySearch(
        array: Array<T>?, value: T, comparator: Comparator<in T>?
    ): Int {
        val nonNullArray = array ?: throw NullPointerException()
        return if (comparator == null) nonNullArray.binarySearch(value)
        else nonNullArray.binarySearch(value, comparator)
    }

    public fun <T> binarySearch(
        array: Array<T>?, value: T, comparator: Comparator<in T>?, fromIndex: Int, toIndex: Int
    ): Int {
        val nonNullArray = array ?: throw NullPointerException()
        return if (comparator == null) nonNullArray.binarySearch(value, fromIndex, toIndex)
        else nonNullArray.binarySearch(value, comparator, fromIndex, toIndex)
    }

    public fun binarySearch(array: ByteArray?, value: Byte, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)
    public fun binarySearch(array: ShortArray?, value: Short, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)
    public fun binarySearch(array: CharArray?, value: Char, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)
    public fun binarySearch(array: IntArray?, value: Int, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)
    public fun binarySearch(array: LongArray?, value: Long, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)
    public fun binarySearch(array: FloatArray?, value: Float, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)
    public fun binarySearch(array: DoubleArray?, value: Double, fromIndex: Int = 0, toIndex: Int = array?.size ?: 0): Int =
        (array ?: throw NullPointerException()).binarySearch(value, fromIndex, toIndex)

    public fun <T> copyOf(array: Array<T>?, newLength: Int): Array<T?> {
        val nonNullArray = array ?: throw NullPointerException()
        checkCopyLength(newLength)
        return nonNullArray.copyOf(newLength)
    }

    public fun copyOf(array: BooleanArray?, newLength: Int): BooleanArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: ByteArray?, newLength: Int): ByteArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: ShortArray?, newLength: Int): ShortArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: CharArray?, newLength: Int): CharArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: IntArray?, newLength: Int): IntArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: LongArray?, newLength: Int): LongArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: FloatArray?, newLength: Int): FloatArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }
    public fun copyOf(array: DoubleArray?, newLength: Int): DoubleArray =
        (array ?: throw NullPointerException()).let { checkCopyLength(newLength); it.copyOf(newLength) }

    public fun <T> copyOfRange(array: Array<T>?, fromIndex: Int, toIndex: Int): Array<T?> {
        val nonNullArray = array ?: throw NullPointerException()
        val length = checkCopyRange(nonNullArray.size, fromIndex, toIndex)
        val result = nonNullArray.copyOf(length)
        var index = 0
        while (index < length) {
            result[index] = null
            index++
        }
        index = 0
        while (index < length && fromIndex + index < nonNullArray.size) {
            result[index] = nonNullArray[fromIndex + index]
            index++
        }
        return result
    }

    public fun copyOfRange(array: BooleanArray?, fromIndex: Int, toIndex: Int): BooleanArray =
        copyBooleanRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: ByteArray?, fromIndex: Int, toIndex: Int): ByteArray =
        copyByteRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: ShortArray?, fromIndex: Int, toIndex: Int): ShortArray =
        copyShortRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: CharArray?, fromIndex: Int, toIndex: Int): CharArray =
        copyCharRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: IntArray?, fromIndex: Int, toIndex: Int): IntArray =
        copyIntRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: LongArray?, fromIndex: Int, toIndex: Int): LongArray =
        copyLongRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: FloatArray?, fromIndex: Int, toIndex: Int): FloatArray =
        copyFloatRange(array ?: throw NullPointerException(), fromIndex, toIndex)
    public fun copyOfRange(array: DoubleArray?, fromIndex: Int, toIndex: Int): DoubleArray =
        copyDoubleRange(array ?: throw NullPointerException(), fromIndex, toIndex)

    public fun <T> sort(array: Array<T>?) {
        (array ?: throw NullPointerException()).sort()
    }

    public fun <T> sort(array: Array<T>?, fromIndex: Int, toIndex: Int) {
        (array ?: throw NullPointerException()).sort(fromIndex, toIndex)
    }

    public fun sort(array: ByteArray?) { sortByteArray(array ?: throw NullPointerException(), 0, array.size) }
    public fun sort(array: ByteArray?, fromIndex: Int, toIndex: Int) { sortByteArray(array ?: throw NullPointerException(), fromIndex, toIndex) }
    public fun sort(array: ShortArray?) { sortShortArray(array ?: throw NullPointerException(), 0, array.size) }
    public fun sort(array: ShortArray?, fromIndex: Int, toIndex: Int) { sortShortArray(array ?: throw NullPointerException(), fromIndex, toIndex) }
    public fun sort(array: CharArray?) { sortCharArray(array ?: throw NullPointerException(), 0, array.size) }
    public fun sort(array: CharArray?, fromIndex: Int, toIndex: Int) { sortCharArray(array ?: throw NullPointerException(), fromIndex, toIndex) }
    public fun sort(array: IntArray?) { (array ?: throw NullPointerException()).sort() }
    public fun sort(array: IntArray?, fromIndex: Int, toIndex: Int) { (array ?: throw NullPointerException()).sort(fromIndex, toIndex) }
    public fun sort(array: LongArray?) { sortLongArray(array ?: throw NullPointerException(), 0, array.size) }
    public fun sort(array: LongArray?, fromIndex: Int, toIndex: Int) { sortLongArray(array ?: throw NullPointerException(), fromIndex, toIndex) }
    public fun sort(array: FloatArray?) { sortFloatArray(array ?: throw NullPointerException(), 0, array.size) }
    public fun sort(array: FloatArray?, fromIndex: Int, toIndex: Int) { sortFloatArray(array ?: throw NullPointerException(), fromIndex, toIndex) }
    public fun sort(array: DoubleArray?) { sortDoubleArray(array ?: throw NullPointerException(), 0, array.size) }
    public fun sort(array: DoubleArray?, fromIndex: Int, toIndex: Int) { sortDoubleArray(array ?: throw NullPointerException(), fromIndex, toIndex) }

    public fun <T> parallelSort(array: Array<T>?) = sort(array)
    public fun <T> parallelSort(array: Array<T>?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: ByteArray?) = sort(array)
    public fun parallelSort(array: ByteArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: ShortArray?) = sort(array)
    public fun parallelSort(array: ShortArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: CharArray?) = sort(array)
    public fun parallelSort(array: CharArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: IntArray?) = sort(array)
    public fun parallelSort(array: IntArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: LongArray?) = sort(array)
    public fun parallelSort(array: LongArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: FloatArray?) = sort(array)
    public fun parallelSort(array: FloatArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)
    public fun parallelSort(array: DoubleArray?) = sort(array)
    public fun parallelSort(array: DoubleArray?, fromIndex: Int, toIndex: Int) = sort(array, fromIndex, toIndex)

    public fun mismatch(first: Array<out Any?>?, second: Array<out Any?>?): Int =
        mismatchArrays(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: BooleanArray?, second: BooleanArray?): Int =
        mismatchBooleans(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: ByteArray?, second: ByteArray?): Int =
        mismatchBytes(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: ShortArray?, second: ShortArray?): Int =
        mismatchShorts(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: CharArray?, second: CharArray?): Int =
        mismatchChars(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: IntArray?, second: IntArray?): Int =
        mismatchInts(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: LongArray?, second: LongArray?): Int =
        mismatchLongs(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: FloatArray?, second: FloatArray?): Int =
        mismatchFloats(first ?: throw NullPointerException(), second ?: throw NullPointerException())
    public fun mismatch(first: DoubleArray?, second: DoubleArray?): Int =
        mismatchDoubles(first ?: throw NullPointerException(), second ?: throw NullPointerException())
}

private fun checkCopyLength(newLength: Int) {
    if (newLength < 0) throw NegativeArraySizeException()
}

private fun checkCopyRange(size: Int, fromIndex: Int, toIndex: Int): Int {
    if (fromIndex > toIndex) throw IllegalArgumentException()
    if (fromIndex < 0 || fromIndex > size) throw ArrayIndexOutOfBoundsException()
    return toIndex - fromIndex
}

private fun checkSortRange(size: Int, fromIndex: Int, toIndex: Int) {
    if (fromIndex > toIndex) throw IllegalArgumentException()
    if (fromIndex < 0 || toIndex > size) throw ArrayIndexOutOfBoundsException()
}

private fun sortByteArray(array: ByteArray, fromIndex: Int, toIndex: Int) {
    checkSortRange(array.size, fromIndex, toIndex)
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(false)
    var index = 0
    while (index < sorted.size) { array[fromIndex + index] = sorted[index]; index++ }
}

private fun sortShortArray(array: ShortArray, fromIndex: Int, toIndex: Int) {
    checkSortRange(array.size, fromIndex, toIndex)
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(false)
    var index = 0
    while (index < sorted.size) { array[fromIndex + index] = sorted[index]; index++ }
}

private fun sortCharArray(array: CharArray, fromIndex: Int, toIndex: Int) {
    checkSortRange(array.size, fromIndex, toIndex)
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(false)
    var index = 0
    while (index < sorted.size) { array[fromIndex + index] = sorted[index]; index++ }
}

private fun sortLongArray(array: LongArray, fromIndex: Int, toIndex: Int) {
    checkSortRange(array.size, fromIndex, toIndex)
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(false)
    var index = 0
    while (index < sorted.size) { array[fromIndex + index] = sorted[index]; index++ }
}

private fun sortFloatArray(array: FloatArray, fromIndex: Int, toIndex: Int) {
    checkSortRange(array.size, fromIndex, toIndex)
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(false)
    var index = 0
    while (index < sorted.size) { array[fromIndex + index] = sorted[index]; index++ }
}

private fun sortDoubleArray(array: DoubleArray, fromIndex: Int, toIndex: Int) {
    checkSortRange(array.size, fromIndex, toIndex)
    val sorted = array.copyOfRange(fromIndex, toIndex)
    sorted.stableSortImpl(false)
    var index = 0
    while (index < sorted.size) { array[fromIndex + index] = sorted[index]; index++ }
}

private fun copyBooleanRange(array: BooleanArray, fromIndex: Int, toIndex: Int): BooleanArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = BooleanArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyByteRange(array: ByteArray, fromIndex: Int, toIndex: Int): ByteArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = ByteArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyShortRange(array: ShortArray, fromIndex: Int, toIndex: Int): ShortArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = ShortArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyCharRange(array: CharArray, fromIndex: Int, toIndex: Int): CharArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = CharArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyIntRange(array: IntArray, fromIndex: Int, toIndex: Int): IntArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = IntArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyLongRange(array: LongArray, fromIndex: Int, toIndex: Int): LongArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = LongArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyFloatRange(array: FloatArray, fromIndex: Int, toIndex: Int): FloatArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = FloatArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun copyDoubleRange(array: DoubleArray, fromIndex: Int, toIndex: Int): DoubleArray {
    val length = checkCopyRange(array.size, fromIndex, toIndex)
    val result = DoubleArray(length)
    var index = 0
    while (index < length && fromIndex + index < array.size) { result[index] = array[fromIndex + index]; index++ }
    return result
}

private fun mismatchArrays(first: Array<out Any?>, second: Array<out Any?>): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) {
        if (!__valuesEqual(first[index], second[index])) return index
        index++
    }
    return if (first.size == second.size) -1 else length
}

private fun mismatchBooleans(first: BooleanArray, second: BooleanArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchBytes(first: ByteArray, second: ByteArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchShorts(first: ShortArray, second: ShortArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchChars(first: CharArray, second: CharArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchInts(first: IntArray, second: IntArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchLongs(first: LongArray, second: LongArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchFloats(first: FloatArray, second: FloatArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}

private fun mismatchDoubles(first: DoubleArray, second: DoubleArray): Int {
    val length = if (first.size < second.size) first.size else second.size
    var index = 0
    while (index < length) { if (!__valuesEqual(first[index], second[index])) return index; index++ }
    return if (first.size == second.size) -1 else length
}
