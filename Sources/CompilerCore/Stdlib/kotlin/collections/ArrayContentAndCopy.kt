package kotlin.collections

import kotlin.internal.__arrayContentDeepEquals
import kotlin.internal.__arrayContentDeepHashCode
import kotlin.internal.__arrayContentDeepToString
import kotlin.internal.__valuesEqual
import kotlin.text.StringBuilder

// KSP-1514
// Array content comparison, hashing, rendering, and deep-content helpers.
// The public API is bundled Kotlin source. Deep traversal remains a private
// runtime bridge because cycle detection must follow array object identity.
// KSP-658's copy helpers remain in this file and are intentionally unchanged.
//
// The old public kk_array_content* and kk_*Array_contentToString symbols are
// not part of the source-backed API anymore.

public infix fun <T> Array<out T>?.contentEquals(other: Array<out T>?): Boolean {
    if (this == null) return other == null
    if (other == null) return false
    val size = this.size
    if (size != other.size) return false
    var i = 0
    while (i < size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public fun <T> Array<out T>?.contentToString(): String {
    if (this == null) return "null"
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

public fun <T> Array<out T>?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) {
        result = 31 * result + (this[i]?.hashCode() ?: 0)
        i++
    }
    return result
}

public fun <T> Array<out T>?.contentDeepEquals(other: Array<out T>?): Boolean {
    val array = this ?: return other == null
    val otherArray = other ?: return false
    return __arrayContentDeepEquals(array, otherArray)
}

public fun <T> Array<out T>?.contentDeepToString(): String {
    val array = this ?: return "null"
    return __arrayContentDeepToString(array)
}

public fun <T> Array<out T>?.contentDeepHashCode(): Int {
    val array = this ?: return 0
    return __arrayContentDeepHashCode(array)
}

// Primitive and unsigned array overloads are source-backed as well. The
// element remains typed at the Kotlin boundary, preserving Float/Double
// NaN and signed-zero behavior in equality, hashing, and rendering.

public infix fun ByteArray?.contentEquals(other: ByteArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun ShortArray?.contentEquals(other: ShortArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun IntArray?.contentEquals(other: IntArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun LongArray?.contentEquals(other: LongArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun FloatArray?.contentEquals(other: FloatArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun DoubleArray?.contentEquals(other: DoubleArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun BooleanArray?.contentEquals(other: BooleanArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun CharArray?.contentEquals(other: CharArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun UByteArray?.contentEquals(other: UByteArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun UShortArray?.contentEquals(other: UShortArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun UIntArray?.contentEquals(other: UIntArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public infix fun ULongArray?.contentEquals(other: ULongArray?): Boolean {
    if (this == null) return other == null
    if (other == null || this.size != other.size) return false
    var i = 0
    while (i < this.size) {
        if (!__valuesEqual(this[i], other[i])) return false
        i++
    }
    return true
}

public fun ByteArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun ShortArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun IntArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun LongArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun FloatArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun DoubleArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun BooleanArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun CharArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun UByteArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun UShortArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun UIntArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun ULongArray?.contentHashCode(): Int {
    if (this == null) return 0
    var result = 1
    var i = 0
    while (i < this.size) { result = 31 * result + this[i].hashCode(); i++ }
    return result
}

public fun ByteArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun ShortArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun IntArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun LongArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun FloatArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun DoubleArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun BooleanArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun CharArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun UByteArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun UShortArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun UIntArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")
public fun ULongArray?.contentToString(): String = if (this == null) "null" else this.joinToString(", ", "[", "]")

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
