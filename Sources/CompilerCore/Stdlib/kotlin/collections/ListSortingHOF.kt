package kotlin.collections

import kotlin.comparisons.reverseOrder
import kotlin.comparisons.naturalOrder
import kotlin.internal.KsSymbolName
import kotlin.random.Random

// MIGRATION-COL-006
// List sorting/comparison HOFs migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//
// KSP-1511 removed the last synthetic ABI fallback (shuffled/shuffled(Random),
// the two members KSP-426 had deliberately kept runtime-backed via
// BundledDeclarationIndex's shuffled retained-overlap case): every member
// below is now the sole, source-backed implementation.

public inline fun <T : Comparable<T>> List<T>.sorted(): List<T> {
    return sortedWith(naturalOrder<T>())
}

public inline fun <T, R : Comparable<R>> List<T>.sortedBy(selector: (T) -> R): List<T> {
    val result = toMutableList()
    result.stableSortBySelector(selector, false)
    return result
}

public inline fun <T, R : Comparable<R>> List<T>.sortedByDescending(selector: (T) -> R?): List<T> {
    val result = toMutableList()
    result.stableSortBySelector(selector, true)
    return result
}

public inline fun <T> List<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val result = toMutableList()
    result.stableSortWith(comparator)
    return result
}

public inline fun <T : Comparable<T>> List<T>.sortedDescending(): List<T> {
    return sortedWith(reverseOrder<T>())
}

public inline fun <T : Comparable<T>> MutableList<T>.sort() {
    sortWith(naturalOrder<T>())
}

public inline fun <T : Comparable<T>> MutableList<T>.sortDescending() {
    sortWith(reverseOrder<T>())
}

public inline fun <T, R : Comparable<R>> MutableList<T>.sortBy(selector: (T) -> R) {
    this.stableSortBySelector(selector, false)
}

public inline fun <T, R : Comparable<R>> MutableList<T>.sortByDescending(selector: (T) -> R) {
    this.stableSortBySelector(selector, true)
}

public inline fun <T> MutableList<T>.sortWith(comparator: Comparator<in T>) {
    this.stableSortWith(comparator)
}

public inline fun <T> List<T>.sortedWith(comparison: (T, T) -> Int): List<T> {
    val result = toMutableList()
    result.stableSortByComparison(comparison)
    return result
}

public inline fun <T> MutableList<T>.sortWith(comparison: (T, T) -> Int) {
    this.stableSortByComparison(comparison)
}

public fun <T> List<T>.shuffled(): List<T> = shuffled(Random.Default)

public fun <T> List<T>.shuffled(random: Random): List<T> {
    val result = mutableListOf<T>()
    var copyIndex = 0
    while (copyIndex < size) {
        result.add(this[copyIndex])
        copyIndex++
    }

    var i = result.size - 1
    while (i > 0) {
        val j = if (random === Random.Default) {
            // Random.Default is represented by the runtime singleton handle,
            // so use the bridge instead of virtual dispatch on that handle
            // (same workaround as MutableList.shuffle(random) below).
            __kk_mutable_list_random_nextInt(random, 0..i)
        } else {
            random.nextInt(i + 1)
        }
        val tmp = result[i]
        result[i] = result[j]
        result[j] = tmp
        i--
    }
    return result
}

// KSP-1021: MutableList collection APIs migrated to Kotlin source.
// The existing runtime reversed-view bridge is intentionally shared with the
// read-only List.asReversed implementation in ListCollectionOps.kt.
@KsSymbolName("__kk_list_as_reversed")
private external fun <T> __kk_mutable_list_as_reversed(list: MutableList<T>): MutableList<T>

public fun <T> MutableList<T>.asReversed(): MutableList<T> {
    return __kk_mutable_list_as_reversed(this)
}

@Deprecated("Use removeAt(index) instead.", ReplaceWith("removeAt(index)"), level = DeprecationLevel.ERROR)
public inline fun <T> MutableList<T>.remove(index: Int): T {
    return removeAt(index)
}

@IgnorableReturnValue
public fun <T> MutableList<T>.removeAll(predicate: (T) -> Boolean): Boolean {
    return filterInPlace(predicate, true)
}

@IgnorableReturnValue
public fun <T> MutableList<T>.retainAll(predicate: (T) -> Boolean): Boolean {
    return filterInPlace(predicate, false)
}

private fun <T> MutableList<T>.filterInPlace(
    predicate: (T) -> Boolean,
    predicateResultToRemove: Boolean
): Boolean {
    val originalSize = size
    var writeIndex = 0
    var readIndex = 0
    while (readIndex < originalSize) {
        val element = this[readIndex]
        if (predicate(element) != predicateResultToRemove) {
            if (writeIndex != readIndex) this[writeIndex] = element
            writeIndex++
        }
        readIndex++
    }

    if (writeIndex >= size) return false
    var removeIndex = originalSize - 1
    while (removeIndex >= writeIndex) {
        removeAt(removeIndex)
        removeIndex--
    }
    return true
}

public fun <T> MutableList<T>.reverse() {
    var left = 0
    var right = size - 1
    while (left < right) {
        val temporary = this[left]
        this[left] = this[right]
        this[right] = temporary
        left++
        right--
    }
}

@SinceKotlin("1.2")
public fun <T> MutableList<T>.shuffle() {
    shuffle(Random.Default)
}

@KsSymbolName("__kk_random_nextInt_rangeObject")
private external fun __kk_mutable_list_random_nextInt(random: Random, range: IntRange): Int

@SinceKotlin("1.3")
public fun <T> MutableList<T>.shuffle(random: Random) {
    var i = size - 1
    while (i > 0) {
        val j = if (random === Random.Default) {
            // Random.Default is represented by the runtime singleton handle,
            // so use the bridge instead of virtual dispatch on that handle.
            __kk_mutable_list_random_nextInt(random, 0..i)
        } else {
            random.nextInt(i + 1)
        }
        val temporary = this[i]
        this[i] = this[j]
        this[j] = temporary
        i--
    }
}
