@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: ULongRange higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - ULongRange

public fun ULongRange.forEach(action: (ULong) -> Unit) {
    for (element in this) { action(element) }
}

public fun ULongRange.reduce(operation: (ULong, ULong) -> ULong): ULong {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun ULongRange.reduceIndexed(operation: (Int, ULong, ULong) -> ULong): ULong {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index++
    }
    return accumulator
}

public fun <R> ULongRange.fold(initial: R, operation: (R, ULong) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> ULongRange.foldIndexed(initial: R, operation: (Int, R, ULong) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun ULongRange.find(predicate: (ULong) -> Boolean): ULong? = firstOrNull(predicate)
public fun ULongRange.findLast(predicate: (ULong) -> Boolean): ULong? = lastOrNull(predicate)

public fun ULongRange.first(predicate: (ULong) -> Boolean): ULong {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun ULongRange.firstOrNull(predicate: (ULong) -> Boolean): ULong? {
    for (element in this) if (predicate(element)) return element
    return null
}

@NoInline
public fun ULongRange.last(predicate: (ULong) -> Boolean): ULong {
    var found = false
    var result = 0uL
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    return result
}

@NoInline
public fun ULongRange.lastOrNull(predicate: (ULong) -> Boolean): ULong? {
    var found = false
    var result = 0uL
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun ULongRange.any(predicate: (ULong) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun ULongRange.all(predicate: (ULong) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun ULongRange.none(predicate: (ULong) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun ULongRange.take(n: Int): List<ULong> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<ULong>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun ULongRange.drop(n: Int): List<ULong> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<ULong>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun ULongRange.chunked(size: Int): List<List<ULong>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<ULong>>()
    var current = mutableListOf<ULong>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<ULong>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun ULongRange.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<ULong>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<ULong>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<ULong>()
        var j = i
        while (j < values.size && j < end) {
            window.add(values[j])
            j++
        }
        result.add(window)
        i += step
    }
    return result
}

public fun <R> ULongRange.map(transform: (ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun ULongRange.filter(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun ULongRange.filterNot(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    for (element in this) { if (!predicate(element)) result.add(element) }
    return result
}

public fun ULongRange.filterIndexed(predicate: (Int, ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> ULongRange.mapIndexed(transform: (Int, ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> ULongRange.mapNotNull(transform: (ULong) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun ULongRange.toList(): List<ULong> {
    val result = mutableListOf<ULong>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step.toULong()
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step.toULong()
        }
    }
    return result
}

public fun ULongRange.firstOrNull(): ULong? = if (isEmpty()) null else first

public fun ULongRange.lastOrNull(): ULong? = if (isEmpty()) null else last

public fun ULongRange.sorted(): List<ULong> = if (step < 0) toList().reversed() else toList()

// KSP-1292: Kotlin 2.3.10 widens unsigned values before using the native
// ULong membership rules. Do not recurse through `contains(ULong)` here:
// overload resolution currently prefers `OpenEndRange.contains`, and
// `endExclusive` cannot be represented when `last == ULong.MAX_VALUE`.
@SinceKotlin("1.5")
public operator fun ULongRange.contains(value: UByte): Boolean =
    ulongRangeContainsWidened(value.toULong())

@SinceKotlin("1.5")
public operator fun ULongRange.contains(value: UInt): Boolean =
    ulongRangeContainsWidened(value.toULong())

@SinceKotlin("1.5")
public operator fun ULongRange.contains(value: UShort): Boolean =
    ulongRangeContainsWidened(value.toULong())

private fun ULongRange.ulongRangeContainsWidened(value: ULong): Boolean =
    first <= last && value >= first && value <= last

public fun ULongRange.count(): Int {
    val count: ULong = if (step > 0) {
        if (first > last) 0uL else (last - first) / step.toULong() + 1uL
    } else if (step < 0) {
        if (first < last) 0uL else (first - last) / (-step).toULong() + 1uL
    } else {
        0uL
    }
    return count.toInt()
}

public fun ULongRange.sum(): ULong {
    var sum = 0uL
    for (element in this) {
        sum += element
    }
    return sum
}

public fun ULongRange.reversed(): ULongProgression = ULongProgression.fromClosedRange(last, first, -step)

