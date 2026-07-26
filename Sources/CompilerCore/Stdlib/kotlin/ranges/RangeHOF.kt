package kotlin.ranges

import kotlin.internal.KsSymbolName

// MIGRATION-RANGE-002
// Range/Progression higher-order functions migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeRangeAndDispatch.swift, RuntimeRangeIntRangeHOF.swift,
//   RuntimeRangeLongRange.swift, RuntimeRangeSharedHOF.swift (kk_range_forEach,
//   kk_range_map, kk_range_filter, kk_range_toList; kk_long_range_* / kk_char_range_*
//   equivalents)
//
// NOTE: `forEach`/`map`/`filter`/`toList`/`count` on Range/Progression receivers are
// currently resolved and dispatched entirely through the hardcoded allow-list in
// CallTypeChecker+RangeMemberFallback.swift (Sema) and the CollectionLiteralLoweringPass
// virtual-call rewrite (codegen) -- neither consults user- or stdlib-declared extension
// functions for range-like receivers. These bodies establish the canonical Kotlin-source
// definition ahead of that dispatch being wired directly to it, matching the pattern
// used by MIGRATION-RANGE-003 (RangeCoercion.kt) and MIGRATION-COL-002 (ListHOF.kt).
//
// `first`, `last`, `step` are intentionally NOT included here: they are
// constant-time field reads with no pure-Kotlin expression available (would
// require introducing new native bridge plumbing for zero behavioral change).
// `count()`, `sum()`, and `reversed()` are now included and wired to the shared
// `kk_range_*` ABI surface.
//
// `count(predicate)` is intentionally NOT included: CallTypeChecker+RangeMemberFallback.swift's
// isValidRangeMemberArity() only accepts a 0-arg `count` for range-like receivers, and (as noted
// above) member resolution for such receivers never falls through to user-declared candidates --
// so a 1-arg overload here would be an uncallable, misleading declaration. Widening that arity
// allow-list is dispatch-wiring work, not a Kotlin-source migration.

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

@KsSymbolName("kk_range_count")
public fun IntRange.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("kk_range_sum")
public fun IntRange.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("kk_range_reversed")
public external fun IntRange.reversed(): IntRange

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

@KsSymbolName("kk_range_count")
public fun IntProgression.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("kk_range_sum")
public fun IntProgression.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("kk_range_reversed")
public external fun IntProgression.reversed(): IntProgression

// MARK: - LongRange

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

@KsSymbolName("kk_range_count")
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

@KsSymbolName("kk_range_sum")
public fun LongRange.sum(): Long {
    var sum = 0L
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("kk_range_reversed")
public external fun LongRange.reversed(): LongProgression

// MARK: - LongProgression

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

@KsSymbolName("kk_range_count")
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

@KsSymbolName("kk_range_sum")
public fun LongProgression.sum(): Long {
    var sum = 0L
    for (element in this) {
        sum += element
    }
    return sum
}

@KsSymbolName("kk_range_reversed")
public external fun LongProgression.reversed(): LongProgression

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

@KsSymbolName("kk_range_count")
public fun CharRange.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("kk_range_sum")
public fun CharRange.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element.code
    }
    return sum
}

@KsSymbolName("kk_range_reversed")
public external fun CharRange.reversed(): CharRange

// MARK: - CharProgression

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

@KsSymbolName("kk_range_count")
public fun CharProgression.count(): Int {
    return if (step > 0) {
        if (first > last) 0 else (last - first) / step + 1
    } else if (step < 0) {
        if (first < last) 0 else (first - last) / (-step) + 1
    } else {
        0
    }
}

@KsSymbolName("kk_range_sum")
public fun CharProgression.sum(): Int {
    var sum = 0
    for (element in this) {
        sum += element.code
    }
    return sum
}

@KsSymbolName("kk_range_reversed")
public external fun CharProgression.reversed(): CharProgression
