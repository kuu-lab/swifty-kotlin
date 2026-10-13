@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: IntRange higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - IntRange

public fun IntRange.forEach(action: (Int) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> IntRange.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun IntRange.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun IntRange.toList(): List<Int> {
    val result = mutableListOf<Int>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun IntRange.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun IntRange.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun IntRange.reversed(): IntProgression

// KSP-1285: Kotlin exposes exact IntRange overloads for the other signed
// primitive integer types. Long values must be range-checked before narrowing.
@kotlin.internal.InlineOnly
public inline operator fun IntRange.contains(value: Byte): Boolean =
    contains(value.toInt())

@kotlin.internal.InlineOnly
public inline operator fun IntRange.contains(value: Long): Boolean {
    if (value < -2147483648L || value > 2147483647L) return false
    return contains(value.toInt())
}

@kotlin.internal.InlineOnly
public inline operator fun IntRange.contains(value: Short): Boolean =
    contains(value.toInt())

public fun IntRange.average(): Double {
    if (isEmpty()) return Double.NaN
    var sum = 0.0
    for (element in this) sum += element.toDouble()
    return sum / count()
}

public fun IntRange.sorted(): List<Int> = if (step < 0) toList().reversed() else toList()

public fun IntRange.take(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun IntRange.drop(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun IntRange.filterNot(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) if (!predicate(element)) result.add(element)
    return result
}

public fun IntRange.filterIndexed(predicate: (Int, Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> IntRange.mapIndexed(transform: (Int, Int) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> IntRange.mapNotNull(transform: (Int) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun IntRange.reduce(operation: (Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun IntRange.reduceIndexed(operation: (Int, Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index++
    }
    return accumulator
}

public fun <R> IntRange.fold(initial: R, operation: (R, Int) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> IntRange.foldIndexed(initial: R, operation: (Int, R, Int) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun IntRange.find(predicate: (Int) -> Boolean): Int? = firstOrNull(predicate)
public fun IntRange.findLast(predicate: (Int) -> Boolean): Int? = lastOrNull(predicate)

public fun IntRange.first(predicate: (Int) -> Boolean): Int {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("No element found matching predicate.")
}

public fun IntRange.firstOrNull(): Int? = if (isEmpty()) null else first
public fun IntRange.firstOrNull(predicate: (Int) -> Boolean): Int? {
    for (element in this) if (predicate(element)) return element
    return null
}

@NoInline
public fun IntRange.last(predicate: (Int) -> Boolean): Int {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("No element found matching predicate.")
    return result
}

public fun IntRange.lastOrNull(): Int? = if (isEmpty()) null else last
@NoInline
public fun IntRange.lastOrNull(predicate: (Int) -> Boolean): Int? {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun IntRange.any(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun IntRange.none(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun IntRange.chunked(size: Int): List<List<Int>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<Int>>()
    var current = mutableListOf<Int>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<Int>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun IntRange.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<Int>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<Int>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<Int>()
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

