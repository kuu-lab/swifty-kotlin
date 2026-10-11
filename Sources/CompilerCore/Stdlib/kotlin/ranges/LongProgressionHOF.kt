@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: LongProgression higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - LongProgression

private fun longProgressionDescription(progression: LongProgression): String {
    // Negate in Long so Long.MIN_VALUE still renders as a positive magnitude.
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun LongProgression.first(): Long {
    if (isEmpty())
        throw NoSuchElementException("Progression ${longProgressionDescription(this)} is empty.")
    return this.first
}

@SinceKotlin("1.7")
public fun LongProgression.firstOrNull(): Long? = if (isEmpty()) null else this.first

@SinceKotlin("1.7")
public fun LongProgression.last(): Long {
    if (isEmpty())
        throw NoSuchElementException("Progression ${longProgressionDescription(this)} is empty.")
    return this.last
}

@SinceKotlin("1.7")
public fun LongProgression.lastOrNull(): Long? = if (isEmpty()) null else this.last

public fun LongProgression.forEach(action: (Long) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> LongProgression.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun LongProgression.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun LongProgression.toList(): List<Long> {
    val result = mutableListOf<Long>()
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

public fun LongProgression.take(n: Int): List<Long> {
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

public fun LongProgression.drop(n: Int): List<Long> {
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

public fun LongProgression.sorted(): List<Long> {
    val elements = toList()
    return if (step < 0L) elements.reversed() else elements
}

public fun LongProgression.average(): Double {
    var sum = 0.0
    var count = 0
    for (element in this) {
        sum += element
        count++
    }
    return if (count > 0) sum / count else 0.0 / 0.0
}

@KsSymbolName("__kk_range_count")
public fun LongProgression.count(): Int {
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
public fun LongProgression.sum(): Long {
    var sum = 0L
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun LongProgression.reversed(): LongProgression

