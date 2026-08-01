package kotlin.collections

import kotlin.internal.__valuesEqual
import kotlin.text.StringBuilder

// KSP-658
// Array<T> content comparison / rendering / copy helpers.
// Migration source: Sources/Runtime/RuntimeArrayDequeAndUtility.swift
//   (kk_array_contentEquals / kk_array_contentToString) and the synthetic
//   Array member stubs.
//
// Equality is delegated to __kk_values_equal via kotlin.internal.__valuesEqual.
// Fresh storage comes from arrayOfNulls, so no runtime bridge is needed for the
// generic Array<T> receiver.

public infix fun <T> Array<T>.contentEquals(other: Array<T>): Boolean {
    val size = this.size
    if (size != other.size) return false
    var i = 0
    while (i < size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public fun <T> Array<T>.contentToString(): String {
    val sb = StringBuilder()
    sb.append("[")
    val size = this.size
    var i = 0
    while (i < size) {
        if (i > 0) sb.append(", ")
        val element = this[i]
        sb.append(if (element == null) "null" else element.toString())
        i++
    }
    sb.append("]")
    return sb.toString()
}

@Suppress("UNCHECKED_CAST")
public fun <T> Array<T>.copyOf(): Array<T> {
    val size = this.size
    val result = arrayOfNulls<T>(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result as Array<T>
}

public fun <T> Array<T>.copyOf(newSize: Int): Array<T?> {
    val result = arrayOfNulls<T>(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var i = 0
    while (i < count) {
        result[i] = this[i]
        i++
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <T> Array<T>.copyOfRange(fromIndex: Int, toIndex: Int): Array<T> {
    val size = this.size
    if (fromIndex < 0 || toIndex > size) {
        throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex, size: $size")
    }
    if (fromIndex > toIndex) {
        throw IllegalArgumentException("fromIndex: $fromIndex > toIndex: $toIndex")
    }
    val count = toIndex - fromIndex
    val result = arrayOfNulls<T>(count)
    var i = 0
    while (i < count) {
        result[i] = this[fromIndex + i]
        i++
    }
    return result as Array<T>
}
