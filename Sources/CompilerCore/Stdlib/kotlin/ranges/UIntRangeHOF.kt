@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002: UIntRange higher-order functions, moved verbatim from RangeHOF.kt.

// MARK: - UIntRange

// KSP-1290: Kotlin exposes concrete UIntRange contains overloads for the
// unsigned primitive types that do not match UInt directly. ULong values must
// be range-checked before narrowing so high bits cannot wrap into UInt.
public operator fun UIntRange.contains(value: UByte): Boolean =
    contains(value.toUInt())

public operator fun UIntRange.contains(value: ULong): Boolean =
    (value shr UInt.SIZE_BITS) == 0uL && contains(value.toUInt())

public operator fun UIntRange.contains(value: UShort): Boolean =
    contains(value.toUInt())

public fun UIntRange.forEach(action: (UInt) -> Unit) {
    for (element in this) { action(element) }
}

public fun UIntRange.reduce(operation: (UInt, UInt) -> UInt): UInt {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public fun UIntRange.reduceIndexed(operation: (Int, UInt, UInt) -> UInt): UInt {
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

public fun <R> UIntRange.fold(initial: R, operation: (R, UInt) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public fun <R> UIntRange.foldIndexed(initial: R, operation: (Int, R, UInt) -> R): R {
    var accumulator = initial
    var index = 0
    for (element in this) {
        accumulator = operation(index, accumulator, element)
        index++
    }
    return accumulator
}

public fun UIntRange.find(predicate: (UInt) -> Boolean): UInt? = firstOrNull(predicate)
public fun UIntRange.findLast(predicate: (UInt) -> Boolean): UInt? = lastOrNull(predicate)

public fun UIntRange.first(predicate: (UInt) -> Boolean): UInt {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun UIntRange.firstOrNull(predicate: (UInt) -> Boolean): UInt? {
    for (element in this) if (predicate(element)) return element
    return null
}

@NoInline
public fun UIntRange.last(predicate: (UInt) -> Boolean): UInt {
    var found = false
    var result = 0u
    for (element in this) if (predicate(element)) { result = element; found = true }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    return result
}

@NoInline
public fun UIntRange.lastOrNull(predicate: (UInt) -> Boolean): UInt? {
    var found = false
    var result = 0u
    for (element in this) if (predicate(element)) { result = element; found = true }
    return if (found) result else null
}

public fun UIntRange.any(predicate: (UInt) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}

public fun UIntRange.all(predicate: (UInt) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public fun UIntRange.none(predicate: (UInt) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return false
    return true
}

public fun UIntRange.take(n: Int): List<UInt> {
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

public fun UIntRange.drop(n: Int): List<UInt> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val result = mutableListOf<UInt>()
    var count = 0
    for (element in this) {
        if (count < n) { count++; continue }
        result.add(element)
    }
    return result
}

public fun UIntRange.chunked(size: Int): List<List<UInt>> {
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

public fun UIntRange.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<UInt>> {
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

public fun <R> UIntRange.map(transform: (UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) { result.add(transform(element)) }
    return result
}

public fun UIntRange.filter(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (predicate(element)) result.add(element) }
    return result
}

public fun UIntRange.filterNot(predicate: (UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    for (element in this) { if (!predicate(element)) result.add(element) }
    return result
}

public fun UIntRange.filterIndexed(predicate: (Int, UInt) -> Boolean): List<UInt> {
    val result = mutableListOf<UInt>()
    var index = 0
    for (element in this) {
        if (predicate(index, element)) result.add(element)
        index++
    }
    return result
}

public fun <R> UIntRange.mapIndexed(transform: (Int, UInt) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        result.add(transform(index, element))
        index++
    }
    return result
}

public fun <R : Any> UIntRange.mapNotNull(transform: (UInt) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val value = transform(element)
        if (value != null) result.add(value)
    }
    return result
}

public fun UIntRange.toList(): List<UInt> {
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

// KSP-1523: no UIntRange.toUIntArray()/average() here — real kotlinc has
// neither (`toUIntArray()` is a `Collection<UInt>` member, and `UIntRange`
// is `Iterable<UInt>` but not `Collection`; `average()` exists only for
// `Iterable<Byte/Short/Int/Long/Float/Double>`, not `UInt`). Confirmed via
// `diff_kotlinc.sh`: real kotlinc rejects both calls on a UIntRange receiver.

public fun UIntRange.firstOrNull(): UInt? = if (isEmpty()) null else first
public fun UIntRange.lastOrNull(): UInt? = if (isEmpty()) null else last

public fun UIntRange.sorted(): List<UInt> = if (step < 0) toList().reversed() else toList()

@KsSymbolName("__kk_range_count")
public fun UIntRange.count(): Int {
    val count: UInt = if (step > 0) {
        if (first > last) 0u else (last - first) / step.toUInt() + 1u
    } else if (step < 0) {
        if (first < last) 0u else (first - last) / (-step).toUInt() + 1u
    } else {
        0u
    }
    return count.toInt()
}

public fun UIntRange.sum(): UInt {
    var sum = 0u
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("__kk_range_reversed")
public external fun UIntRange.reversed(): UIntProgression

