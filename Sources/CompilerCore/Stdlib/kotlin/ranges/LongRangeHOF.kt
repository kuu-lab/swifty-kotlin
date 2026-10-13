@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: LongRange higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - LongRange

// KSP-1287: Kotlin exposes exact LongRange overloads for the other signed
// primitive integer types; widening preserves their values before membership.
@kotlin.internal.InlineOnly
public inline operator fun LongRange.contains(value: Byte): Boolean =
    this.contains(value.toLong())

@kotlin.internal.InlineOnly
public inline operator fun LongRange.contains(value: Int): Boolean =
    this.contains(value.toLong())

@kotlin.internal.InlineOnly
public inline operator fun LongRange.contains(value: Short): Boolean =
    this.contains(value.toLong())

public fun LongRange.forEach(action: (Long) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> LongRange.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun LongRange.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun LongRange.toList(): List<Long> {
    val result = mutableListOf<Long>()
    if (step > 0L) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    } else if (step < 0L) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step
        }
    }
    return result
}

public fun LongRange.take(n: Int): List<Long> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Long>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun LongRange.drop(n: Int): List<Long> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Long>()
    var skipped = 0
    for (element in this) {
        if (skipped < n) {
            skipped++
            continue
        }
        result.add(element)
    }
    return result
}

public fun LongRange.sorted(): List<Long> {
    val elements = toList()
    return if (step < 0L) elements.reversed() else elements
}

public fun LongRange.average(): Double {
    var sum = 0.0
    var count = 0
    for (element in this) {
        sum += element
        count++
    }
    return if (count > 0) sum / count else 0.0 / 0.0
}

@KsSymbolName("__kk_range_count")
public fun LongRange.count(): Int {
    val first = first.toLong()
    val last = last.toLong()
    val step = step.toLong()
    val count = if (step > 0L) {
        if (first > last) 0L else (last - first) / step + 1L
    } else if (step < 0L) {
        if (first < last) 0L else (first - last) / (-step) + 1L
    } else {
        0L
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun LongRange.sum(): Long {
    var sum = 0L
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun LongRange.reversed(): LongProgression

