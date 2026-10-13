@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: ULongProgression higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - ULongProgression

private fun ulongProgressionDescription(progression: ULongProgression): String {
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun ULongProgression.first(): ULong {
    if (isEmpty())
        throw NoSuchElementException("Progression ${ulongProgressionDescription(this)} is empty.")
    return this.first
}

@SinceKotlin("1.7")
public fun ULongProgression.firstOrNull(): ULong? = if (isEmpty()) null else this.first

@SinceKotlin("1.7")
public fun ULongProgression.last(): ULong {
    if (isEmpty())
        throw NoSuchElementException("Progression ${ulongProgressionDescription(this)} is empty.")
    return this.last
}

@SinceKotlin("1.7")
public fun ULongProgression.lastOrNull(): ULong? = if (isEmpty()) null else this.last

public fun ULongProgression.forEach(action: (ULong) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> ULongProgression.map(transform: (ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun ULongProgression.filter(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun ULongProgression.filterNot(predicate: (ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    for (element in this) { if (!predicate(element)) result.add(element) }
    return result
}

public fun ULongProgression.take(n: Int): List<ULong> {
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

public fun ULongProgression.drop(n: Int): List<ULong> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<ULong>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun ULongProgression.chunked(size: Int): List<List<ULong>> {
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

public fun ULongProgression.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<ULong>> {
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

public fun ULongProgression.filterIndexed(predicate: (Int, ULong) -> Boolean): List<ULong> {
    val result = mutableListOf<ULong>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> ULongProgression.mapIndexed(transform: (Int, ULong) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> ULongProgression.mapNotNull(transform: (ULong) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun ULongProgression.toList(): List<ULong> {
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

public fun ULongProgression.count(): Int {
    val count: ULong = if (step > 0) {
        if (first > last) 0uL else (last - first) / step.toULong() + 1uL
    } else if (step < 0) {
        if (first < last) 0uL else (first - last) / (-step).toULong() + 1uL
    } else {
        0uL
    }
    return count.toInt()
}

public fun ULongProgression.sum(): ULong {
    var sum = 0uL
    for (element in this) {
        sum += element
    }
    return sum
}

public fun ULongProgression.reversed(): ULongProgression = ULongProgression.fromClosedRange(last, first, -step)
