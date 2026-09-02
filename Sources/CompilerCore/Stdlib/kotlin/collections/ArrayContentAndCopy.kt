@file:Suppress("UNCHECKED_CAST")

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
// KSP-1515: Array copy helpers are bundled Kotlin source. The allocation core
// remains compiler/runtime-provided through the array constructors.
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
    if (newSize < 0) {
        throw IllegalArgumentException("Invalid new array size: $newSize.")
    }
    val source = copyOf()
    val size = source.size
    @Suppress("UNCHECKED_CAST")
    val result = arrayOfNulls<T>(newSize) as Array<T>
    val count = if (newSize < size) newSize else size
    var i = 0
    while (i < count) {
        result[i] = source[i]
        i++
    }
    @Suppress("UNCHECKED_CAST")
    return result as Array<T?>
}

@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun <T> Array<T>.copyOf(newSize: Int, init: (Int) -> T): Array<T> {
    if (newSize < 0) {
        throw IllegalArgumentException("Invalid new array size: $newSize.")
    }
    val oldSize = this.size
    @Suppress("UNCHECKED_CAST")
    val copy = copyOf(newSize) as Array<T>
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}

@Suppress("UNCHECKED_CAST")
public fun <T> Array<T>.copyOfRange(fromIndex: Int, toIndex: Int): Array<T> {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val count = toIndex - fromIndex
    @Suppress("UNCHECKED_CAST")
    val result = arrayOfNulls<T>(count) as Array<T>
    var i = 0
    while (i < count) {
        result[i] = this[fromIndex + i]
        i++
    }
    return result
}

public fun <T> Array<out T>.copyInto(
    destination: Array<T>,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): Array<T> {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    @Suppress("UNCHECKED_CAST")
    val source = arrayOfNulls<T>(endIndex - startIndex) as Array<T>
    var index = 0
    while (index < source.size) {
        source[index] = this[startIndex + index]
        index++
    }
    index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

private fun requireCopyOfSize(newSize: Int) {
    require(newSize >= 0) { "Invalid new array size: $newSize." }
}

private fun checkCopyOfRangeArguments(size: Int, fromIndex: Int, toIndex: Int) {
    if (fromIndex < 0 || toIndex > size) {
        throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex, size: $size")
    }
    if (fromIndex > toIndex) {
        throw IllegalArgumentException("fromIndex: $fromIndex > toIndex: $toIndex")
    }
}

private fun checkCopyIntoArguments(
    sourceSize: Int,
    destinationSize: Int,
    destinationOffset: Int,
    startIndex: Int,
    endIndex: Int,
) {
    if (startIndex < 0 || endIndex > sourceSize) {
        throw IndexOutOfBoundsException(
            "startIndex: $startIndex, endIndex: $endIndex, size: $sourceSize"
        )
    }
    if (startIndex > endIndex) {
        throw IllegalArgumentException("startIndex: $startIndex > endIndex: $endIndex")
    }
    val count = endIndex - startIndex
    if (destinationOffset < 0 || destinationOffset > destinationSize - count) {
        throw IndexOutOfBoundsException(
            "destinationOffset: $destinationOffset, size: $destinationSize, count: $count"
        )
    }
}

// Primitive and unsigned array overloads use typed constructors and indexed
// access so element boxing stays at the compiler-provided array boundary.

public fun IntArray.copyOf(): IntArray = copyOf(this.size)
public fun IntArray.copyOf(newSize: Int): IntArray {
    requireCopyOfSize(newSize)
    val result = IntArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun IntArray.copyOf(newSize: Int, init: (Int) -> Int): IntArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun IntArray.copyOfRange(fromIndex: Int, toIndex: Int): IntArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = IntArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun IntArray.copyInto(
    destination: IntArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): IntArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun LongArray.copyOf(): LongArray = copyOf(this.size)
public fun LongArray.copyOf(newSize: Int): LongArray {
    requireCopyOfSize(newSize)
    val result = LongArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun LongArray.copyOf(newSize: Int, init: (Int) -> Long): LongArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun LongArray.copyOfRange(fromIndex: Int, toIndex: Int): LongArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = LongArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun LongArray.copyInto(
    destination: LongArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): LongArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun ShortArray.copyOf(): ShortArray = copyOf(this.size)
public fun ShortArray.copyOf(newSize: Int): ShortArray {
    requireCopyOfSize(newSize)
    val result = ShortArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun ShortArray.copyOf(newSize: Int, init: (Int) -> Short): ShortArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun ShortArray.copyOfRange(fromIndex: Int, toIndex: Int): ShortArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = ShortArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun ShortArray.copyInto(
    destination: ShortArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): ShortArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun ByteArray.copyOf(): ByteArray = copyOf(this.size)
public fun ByteArray.copyOf(newSize: Int): ByteArray {
    requireCopyOfSize(newSize)
    val result = ByteArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun ByteArray.copyOf(newSize: Int, init: (Int) -> Byte): ByteArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun ByteArray.copyOfRange(fromIndex: Int, toIndex: Int): ByteArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = ByteArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun ByteArray.copyInto(
    destination: ByteArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): ByteArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun CharArray.copyOf(): CharArray = copyOf(this.size)
public fun CharArray.copyOf(newSize: Int): CharArray {
    requireCopyOfSize(newSize)
    val result = CharArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun CharArray.copyOf(newSize: Int, init: (Int) -> Char): CharArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun CharArray.copyOfRange(fromIndex: Int, toIndex: Int): CharArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = CharArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun CharArray.copyInto(
    destination: CharArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): CharArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun BooleanArray.copyOf(): BooleanArray = copyOf(this.size)
public fun BooleanArray.copyOf(newSize: Int): BooleanArray {
    requireCopyOfSize(newSize)
    val result = BooleanArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun BooleanArray.copyOf(newSize: Int, init: (Int) -> Boolean): BooleanArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun BooleanArray.copyOfRange(fromIndex: Int, toIndex: Int): BooleanArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = BooleanArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun BooleanArray.copyInto(
    destination: BooleanArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): BooleanArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun FloatArray.copyOf(): FloatArray = copyOf(this.size)
public fun FloatArray.copyOf(newSize: Int): FloatArray {
    requireCopyOfSize(newSize)
    val result = FloatArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun FloatArray.copyOf(newSize: Int, init: (Int) -> Float): FloatArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun FloatArray.copyOfRange(fromIndex: Int, toIndex: Int): FloatArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = FloatArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun FloatArray.copyInto(
    destination: FloatArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): FloatArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun DoubleArray.copyOf(): DoubleArray = copyOf(this.size)
public fun DoubleArray.copyOf(newSize: Int): DoubleArray {
    requireCopyOfSize(newSize)
    val result = DoubleArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun DoubleArray.copyOf(newSize: Int, init: (Int) -> Double): DoubleArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun DoubleArray.copyOfRange(fromIndex: Int, toIndex: Int): DoubleArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = DoubleArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun DoubleArray.copyInto(
    destination: DoubleArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): DoubleArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun UByteArray.copyOf(): UByteArray = copyOf(this.size)
public fun UByteArray.copyOf(newSize: Int): UByteArray {
    requireCopyOfSize(newSize)
    val result = UByteArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun UByteArray.copyOf(newSize: Int, init: (Int) -> UByte): UByteArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun UByteArray.copyOfRange(fromIndex: Int, toIndex: Int): UByteArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = UByteArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun UByteArray.copyInto(
    destination: UByteArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): UByteArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun UShortArray.copyOf(): UShortArray = copyOf(this.size)
public fun UShortArray.copyOf(newSize: Int): UShortArray {
    requireCopyOfSize(newSize)
    val result = UShortArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun UShortArray.copyOf(newSize: Int, init: (Int) -> UShort): UShortArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun UShortArray.copyOfRange(fromIndex: Int, toIndex: Int): UShortArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = UShortArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun UShortArray.copyInto(
    destination: UShortArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): UShortArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun UIntArray.copyOf(): UIntArray = copyOf(this.size)
public fun UIntArray.copyOf(newSize: Int): UIntArray {
    requireCopyOfSize(newSize)
    val result = UIntArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun UIntArray.copyOf(newSize: Int, init: (Int) -> UInt): UIntArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun UIntArray.copyOfRange(fromIndex: Int, toIndex: Int): UIntArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = UIntArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun UIntArray.copyInto(
    destination: UIntArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): UIntArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}

public fun ULongArray.copyOf(): ULongArray = copyOf(this.size)
public fun ULongArray.copyOf(newSize: Int): ULongArray {
    requireCopyOfSize(newSize)
    val result = ULongArray(newSize)
    val count = if (newSize < this.size) newSize else this.size
    var index = 0
    while (index < count) {
        result[index] = this[index]
        index++
    }
    return result
}
@ExperimentalStdlibApi
@SinceKotlin("2.2")
public inline fun ULongArray.copyOf(newSize: Int, init: (Int) -> ULong): ULongArray {
    requireCopyOfSize(newSize)
    val oldSize = this.size
    val copy = copyOf(newSize)
    var index = oldSize
    while (index < newSize) {
        copy[index] = init(index)
        index++
    }
    return copy
}
public fun ULongArray.copyOfRange(fromIndex: Int, toIndex: Int): ULongArray {
    checkCopyOfRangeArguments(this.size, fromIndex, toIndex)
    val result = ULongArray(toIndex - fromIndex)
    var index = 0
    while (index < result.size) {
        result[index] = this[fromIndex + index]
        index++
    }
    return result
}
public fun ULongArray.copyInto(
    destination: ULongArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = this.size,
): ULongArray {
    checkCopyIntoArguments(this.size, destination.size, destinationOffset, startIndex, endIndex)
    val source = copyOfRange(startIndex, endIndex)
    var index = 0
    while (index < source.size) {
        destination[destinationOffset + index] = source[index]
        index++
    }
    return destination
}
