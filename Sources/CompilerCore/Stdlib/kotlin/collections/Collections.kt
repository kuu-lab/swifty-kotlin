package kotlin.collections

import kotlin.contracts.contract
import kotlin.random.Random

// KSP-435
// Generic Collection<T> conversions migrated from the Swift runtime
// `kk_collection_*` bridges. `size` / `isEmpty()` stay native because they are
// abstract interface members whose implementation depends on the runtime box
// type tag; they are reachable through the `__kk_collection_*` bridges.

@Suppress("UNCHECKED_CAST")
public fun <T> Collection<T>.toTypedArray(): Array<T> {
    val result = arrayOfNulls<Any?>(size)
    var index = 0
    for (element in this) {
        result[index] = element
        index++
    }
    return result as Array<T>
}

/**
 * Returns the number of elements in this collection.
 */
@kotlin.internal.InlineOnly
public inline fun <T> Collection<T>.count(): Int = size

/**
 * Returns an [IntRange] of the valid indices for this collection.
 *
 * Generic extension properties are represented as zero-argument functions in
 * this bundled source because the parser exposes them through property-style
 * member lookup.
 */
public fun Collection<*>.indices(): IntRange = 0..size - 1

/**
 * Returns `true` if this nullable collection is either null or empty.
 */
@SinceKotlin("1.3")
@kotlin.internal.InlineOnly
@OptIn(kotlin.contracts.ExperimentalContracts::class)
public inline fun <T> Collection<T>?.isNullOrEmpty(): Boolean {
    contract {
        returns(false) implies (this != null)
    }
    return this == null || this.isEmpty()
}

/**
 * Returns this collection if it's not `null` and the empty list otherwise.
 */
@kotlin.internal.InlineOnly
public inline fun <T> Collection<T>?.orEmpty(): Collection<T> = this ?: emptyList<T>()

/**
 * Checks if all elements in the specified collection are contained in this
 * collection.
 */
@Suppress("EXTENSION_SHADOWED_BY_MEMBER")
@kotlin.internal.InlineOnly
public inline fun <@kotlin.internal.OnlyInputTypes T> Collection<T>.containsAll(
    elements: Collection<T>
): Boolean {
    for (element in elements) {
        if (!contains(element)) return false
    }
    return true
}

/**
 * Returns a list containing all elements of this collection and then the
 * given element.
 */
public operator fun <T> Collection<T>.plus(element: T): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}

/**
 * Returns a list containing all elements of this collection and then all
 * elements of the given array.
 */
public operator fun <T> Collection<T>.plus(elements: Array<out T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (element in elements) result.add(element)
    return result
}

/**
 * Returns a list containing all elements of this collection and then all
 * elements of the given iterable.
 */
public operator fun <T> Collection<T>.plus(elements: Iterable<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (element in elements) result.add(element)
    return result
}

/**
 * Returns a list containing all elements of this collection and then all
 * elements of the given sequence.
 */
public operator fun <T> Collection<T>.plus(elements: Sequence<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (element in elements) result.add(element)
    return result
}

/**
 * Returns a list containing all elements of this collection and then the
 * given element.
 */
@kotlin.internal.InlineOnly
public inline fun <T> Collection<T>.plusElement(element: T): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}

/**
 * Returns a random element from this collection, or throws if it is empty.
 */
@SinceKotlin("1.3")
@kotlin.internal.InlineOnly
public inline fun <T> Collection<T>.random(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    val target = Random.nextInt(size)
    var index = 0
    for (element in this) {
        if (index == target) return element
        index++
    }
    throw IndexOutOfBoundsException("Collection doesn't contain element at index $target.")
}

/**
 * Returns a random element from this collection using the specified random
 * source, or throws if it is empty.
 */
@SinceKotlin("1.3")
public fun <T> Collection<T>.random(random: Random): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    val target = random.nextInt(size)
    var index = 0
    for (element in this) {
        if (index == target) return element
        index++
    }
    throw IndexOutOfBoundsException("Collection doesn't contain element at index $target.")
}

/**
 * Returns a random element from this collection, or `null` if it is empty.
 */
@SinceKotlin("1.4")
@kotlin.internal.InlineOnly
public inline fun <T> Collection<T>.randomOrNull(): T? {
    if (isEmpty()) return null
    val target = Random.nextInt(size)
    var index = 0
    for (element in this) {
        if (index == target) return element
        index++
    }
    return null
}

/**
 * Returns a random element from this collection using the specified random
 * source, or `null` if it is empty.
 */
@SinceKotlin("1.4")
public fun <T> Collection<T>.randomOrNull(random: Random): T? {
    if (isEmpty()) return null
    val target = random.nextInt(size)
    var index = 0
    for (element in this) {
        if (index == target) return element
        index++
    }
    return null
}

/**
 * Returns a new mutable list filled with all elements of this collection.
 */
public fun <T> Collection<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

/**
 * Returns an array of Boolean containing all of the elements of this
 * collection.
 */
public fun Collection<Boolean>.toBooleanArray(): BooleanArray {
    val result = BooleanArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Byte containing all of the elements of this collection.
 */
public fun Collection<Byte>.toByteArray(): ByteArray {
    val result = ByteArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Char containing all of the elements of this collection.
 */
public fun Collection<Char>.toCharArray(): CharArray {
    val result = CharArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Double containing all of the elements of this
 * collection.
 */
public fun Collection<Double>.toDoubleArray(): DoubleArray {
    val result = DoubleArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Float containing all of the elements of this collection.
 */
public fun Collection<Float>.toFloatArray(): FloatArray {
    val result = FloatArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Int containing all of the elements of this collection.
 */
public fun Collection<Int>.toIntArray(): IntArray {
    val result = IntArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Long containing all of the elements of this collection.
 */
public fun Collection<Long>.toLongArray(): LongArray {
    val result = LongArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of Short containing all of the elements of this collection.
 */
public fun Collection<Short>.toShortArray(): ShortArray {
    val result = ShortArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of UByte containing all of the elements of this collection.
 */
@SinceKotlin("1.3")
public fun Collection<UByte>.toUByteArray(): UByteArray {
    val result = UByteArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of UShort containing all of the elements of this
 * collection.
 */
@SinceKotlin("1.3")
public fun Collection<UShort>.toUShortArray(): UShortArray {
    val result = UShortArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of UInt containing all of the elements of this collection.
 */
@SinceKotlin("1.3")
public fun Collection<UInt>.toUIntArray(): UIntArray {
    val result = UIntArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}

/**
 * Returns an array of ULong containing all of the elements of this collection.
 */
@SinceKotlin("1.3")
public fun Collection<ULong>.toULongArray(): ULongArray {
    val result = ULongArray(size)
    var index = 0
    for (element in this) result[index++] = element
    return result
}
