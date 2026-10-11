@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: IntProgression higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - IntProgression

public fun IntProgression.forEach(action: (Int) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> IntProgression.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun IntProgression.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun IntProgression.toList(): List<Int> {
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
public fun IntProgression.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun IntProgression.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun IntProgression.reversed(): IntProgression

public fun IntProgression.average(): Double {
    if (isEmpty()) return Double.NaN
    var sum = 0.0
    for (element in this) sum += element.toDouble()
    return sum / count()
}

public fun IntProgression.sorted(): List<Int> = if (step < 0) toList().reversed() else toList()

public fun IntProgression.take(n: Int): List<Int> {
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

public fun IntProgression.drop(n: Int): List<Int> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<Int>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun IntProgression.filterNot(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (element in this) if (!predicate(element)) result.add(element)
    return result
}

public fun IntProgression.filterIndexed(predicate: (Int, Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> IntProgression.mapIndexed(transform: (Int, Int) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> IntProgression.mapNotNull(transform: (Int) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun IntProgression.reduce(operation: (Int, Int) -> Int): Int {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun IntProgression.reduceIndexed(operation: (Int, Int, Int) -> Int): Int {
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

public fun <R> IntProgression.fold(initial: R, operation: (R, Int) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> IntProgression.foldIndexed(initial: R, operation: (Int, R, Int) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun IntProgression.find(predicate: (Int) -> Boolean): Int? = firstOrNull(predicate)
public fun IntProgression.findLast(predicate: (Int) -> Boolean): Int? = lastOrNull(predicate)

private fun intProgressionDescription(progression: IntProgression): String {
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun IntProgression.first(): Int {
    if (isEmpty())
        throw NoSuchElementException("Progression ${intProgressionDescription(this)} is empty.")
    return this.first
}

public fun IntProgression.first(predicate: (Int) -> Boolean): Int {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("No element found matching predicate.")
}

public fun IntProgression.firstOrNull(): Int? = if (isEmpty()) null else first
public fun IntProgression.firstOrNull(predicate: (Int) -> Boolean): Int? {
    for (element in this) if (predicate(element)) return element
    return null
}

@SinceKotlin("1.7")
public fun IntProgression.last(): Int {
    if (isEmpty())
        throw NoSuchElementException("Progression ${intProgressionDescription(this)} is empty.")
    return this.last
}

@NoInline
public fun IntProgression.last(predicate: (Int) -> Boolean): Int {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("No element found matching predicate.")
    return result
}

public fun IntProgression.lastOrNull(): Int? = if (isEmpty()) null else last
@NoInline
public fun IntProgression.lastOrNull(predicate: (Int) -> Boolean): Int? {
    var found = false
    var result = 0
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun IntProgression.any(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun IntProgression.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun IntProgression.none(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun IntProgression.chunked(size: Int): List<List<Int>> {
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

public fun IntProgression.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<Int>> {
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

