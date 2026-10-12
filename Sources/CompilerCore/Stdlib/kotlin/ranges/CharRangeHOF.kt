@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: CharRange higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - CharRange

public fun CharRange.forEach(action: (Char) -> Unit) {
    for (element in this) { action(element) }
}

public fun <R> CharRange.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun CharRange.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun CharRange.toList(): List<Char> {
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

// CharRange uses an integer-shaped runtime representation. Append each value
// as Char here instead of erasing it through the generic Iterable join path.
public fun CharRange.joinToString(
    separator: CharSequence = ", ",
    prefix: CharSequence = "",
    postfix: CharSequence = "",
    limit: Int = -1,
    truncated: CharSequence = "..."
): String {
    val buffer = StringBuilder()
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    for (element in this) {
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(element)
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer.toString()
}

public fun CharRange.take(n: Int): List<Char> {
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

public fun CharRange.drop(n: Int): List<Char> {
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

public fun CharRange.sorted(): List<Char> {
    val elements = toList()
    return if (step < 0) elements.reversed() else elements
}

@KsSymbolName("__kk_range_count")
public fun CharRange.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("__kk_range_sum")
public fun CharRange.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element.code
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun CharRange.reversed(): CharRange

