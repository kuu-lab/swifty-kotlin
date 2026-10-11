@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: UIntProgression higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - UIntProgression

private fun uintProgressionDescription(progression: UIntProgression): String {
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun UIntProgression.first(): UInt {
    if (isEmpty())
        throw NoSuchElementException("Progression ${uintProgressionDescription(this)} is empty.")
    return this.first
}

@SinceKotlin("1.7")
public fun UIntProgression.firstOrNull(): UInt? = if (isEmpty()) null else this.first

@SinceKotlin("1.7")
public fun UIntProgression.last(): UInt {
    if (isEmpty())
        throw NoSuchElementException("Progression ${uintProgressionDescription(this)} is empty.")
    return this.last
}

@SinceKotlin("1.7")
public fun UIntProgression.lastOrNull(): UInt? = if (isEmpty()) null else this.last

public fun UIntProgression.forEach(action: (UInt) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> UIntProgression.map(transform: (UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun UIntProgression.filter(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun UIntProgression.filterNot(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (!predicate(element)) result.add(element) }
    return result
}

public fun UIntProgression.take(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun UIntProgression.drop(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun UIntProgression.chunked(size: Int): List<List<UInt>> {
    require(size > 0) { "size $size must be greater than zero." }
    val result = mutableListOf<List<UInt>>()
    var current = mutableListOf<UInt>()
    for (element in this) {
        current.add(element)
        if (current.size == size) {
            result.add(current)
            current = mutableListOf<UInt>()
        }
    }
    if (current.isNotEmpty()) result.add(current)
    return result
}

public fun UIntProgression.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<UInt>> {
    require(size > 0 && step > 0) { "Both size $size and step $step must be greater than zero." }
    val result = mutableListOf<List<UInt>>()
    val values = toList()
    var i = 0
    while (i < values.size) {
        val end = i + size
        if (end > values.size && !partialWindows) break
        val window = mutableListOf<UInt>()
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

public fun UIntProgression.filterIndexed(predicate: (Int, UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> UIntProgression.mapIndexed(transform: (Int, UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> UIntProgression.mapNotNull(transform: (UInt) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun UIntProgression.toList(): List<UInt> {
    val result = mutableListOf<UInt>()
    if (step > 0) {
        var current = first
        while (current <= last) {
            result.add(current)
            if (current == last) break
            current += step.toUInt()
        }
    } else if (step < 0) {
        var current = first
        while (current >= last) {
            result.add(current)
            if (current == last) break
            current += step.toUInt()
        }
    }
    return result
}

@KsSymbolName("__kk_range_count")
public fun UIntProgression.count(): Int {
    val count: UInt = if (step > 0) {
        if (first > last) 0u else (last - first) / step.toUInt() + 1u
    } else if (step < 0) {
        if (first < last) 0u else (first - last) / (-step).toUInt() + 1u
    } else {
        0u
    }
    return count.toInt()
}

@KsSymbolName("__kk_range_sum")
public fun UIntProgression.sum(): UInt {
    var sum = 0u
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun UIntProgression.reversed(): UIntProgression

