@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: CharProgression higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - CharProgression

private fun charProgressionDescription(progression: CharProgression): String {
    val step = progression.step
    return if (step > 0) {
        "${progression.first}..${progression.last} step $step"
    } else {
        "${progression.first} downTo ${progression.last} step ${-step}"
    }
}

@SinceKotlin("1.7")
public fun CharProgression.first(): Char {
    if (isEmpty()) throw NoSuchElementException("Progression ${charProgressionDescription(this)} is empty.")
    return this.first
}

@SinceKotlin("1.7")
public fun CharProgression.firstOrNull(): Char? = if (isEmpty()) null else this.first

@SinceKotlin("1.7")
public fun CharProgression.last(): Char {
    if (isEmpty()) throw NoSuchElementException("Progression ${charProgressionDescription(this)} is empty.")
    return this.last
}

@SinceKotlin("1.7")
public fun CharProgression.lastOrNull(): Char? = if (isEmpty()) null else this.last

public fun CharProgression.forEach(action: (Char) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> CharProgression.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun CharProgression.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun CharProgression.toList(): List<Char> {
    val result = mutableListOf<Char>()
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

public fun CharProgression.take(n: Int): List<Char> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Char>()
    var count = 0
    for (element in this) {
        if (count >= n) break
        result.add(element)
        count++
    }
    return result
}

public fun CharProgression.drop(n: Int): List<Char> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<Char>()
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

public fun CharProgression.sorted(): List<Char> {
    val elements = toList()
    return if (step < 0) elements.reversed() else elements
}

@KsSymbolName("__kk_range_count")
public fun CharProgression.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun CharProgression.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element.code
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun CharProgression.reversed(): CharProgression

