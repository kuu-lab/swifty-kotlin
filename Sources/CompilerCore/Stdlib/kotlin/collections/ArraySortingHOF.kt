package kotlin.collections

import kotlin.comparisons.compareValues

// KSP-659
// Array `sorted*` / `binarySearch` migrated to bundled Kotlin source.
// The comparison core reuses the KSP-309 Comparator Kotlin implementation
// (kotlin/comparisons/Comparators.kt) for the *With overloads and
// kotlin.comparisons.compareValues for natural-order search.
//
// Migration source:
//   Sources/Runtime/RuntimeArrayDequeAndUtility.swift (kk_array_sortedArray*)
//   Sources/Runtime/RuntimeCollectionHOFArray.swift    (kk_array_sortedArrayWith / kk_array_binarySearch_compare)
//   Sources/Runtime/RuntimeArrayBasics.swift           (kk_array_binarySearch / kk_<prim>Array_binarySearch)
//
// The sorts are stable insertion sorts, matching the tie-breaking of the
// previous runtime implementations and kotlinc's `sorted*` contract.

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

// --- Array<T> sorted* ---------------------------------------------------------

public fun <T : Comparable<T>> Array<T>.sortedArray(): Array<T> {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j].compareTo(element) > 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun <T : Comparable<T>> Array<T>.sortedArrayDescending(): Array<T> {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j].compareTo(element) < 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun <T> Array<T>.sortedArrayWith(comparator: Comparator<in T>): Array<T> {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && comparator.compare(result[j], element) > 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

// --- Array<T> binarySearch ----------------------------------------------------

public fun <T> Array<T>.binarySearch(element: T, fromIndex: Int = 0, toIndex: Int = this.size): Int {
    checkBinarySearchBounds(this.size, fromIndex, toIndex)
    var low = fromIndex
    var high = toIndex - 1
    while (low <= high) {
        val mid = (low + high) ushr 1
        val cmp = compareValues(this[mid], element)
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

// --- Primitive arrays: sortedArray / sortedArrayDescending / binarySearch ------

public fun IntArray.sortedArray(): IntArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun IntArray.sortedArrayDescending(): IntArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun LongArray.sortedArrayDescending(): LongArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun ByteArray.sortedArrayDescending(): ByteArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun ShortArray.sortedArrayDescending(): ShortArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun CharArray.sortedArrayDescending(): CharArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j].compareTo(element) > 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun DoubleArray.sortedArrayDescending(): DoubleArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j].compareTo(element) < 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j].compareTo(element) > 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun FloatArray.sortedArrayDescending(): FloatArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j].compareTo(element) < 0) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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

public fun UByteArray.sortedArray(): UByteArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun UByteArray.sortedArrayDescending(): UByteArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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

public fun UShortArray.sortedArray(): UShortArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun UShortArray.sortedArrayDescending(): UShortArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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

public fun UIntArray.sortedArray(): UIntArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun UIntArray.sortedArrayDescending(): UIntArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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

public fun ULongArray.sortedArray(): ULongArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] > element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
}

public fun ULongArray.sortedArrayDescending(): ULongArray {
    val result = this.copyOf()
    val n = result.size
    var i = 1
    while (i < n) {
        val element = result[i]
        var j = i - 1
        while (j >= 0 && result[j] < element) {
            result[j + 1] = result[j]
            j -= 1
        }
        result[j + 1] = element
        i += 1
    }
    return result
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
