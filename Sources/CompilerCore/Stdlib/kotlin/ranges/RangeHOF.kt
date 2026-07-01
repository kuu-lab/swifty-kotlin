package kotlin.ranges

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
// `first`, `last`, `step`, `reversed()` are intentionally NOT included here: they are
// constant-time field reads/transforms with no pure-Kotlin expression available (would
// require introducing new native bridge plumbing for zero behavioral change) and already
// have complete, correctly-typed Sema declarations via HeaderHelpers+SyntheticTypedRangeStubs.swift
// / HeaderHelpers+SyntheticRangeProgressionStubs.swift.
//
// `count(predicate)` is intentionally NOT included: CallTypeChecker+RangeMemberFallback.swift's
// isValidRangeMemberArity() only accepts a 0-arg `count` for range-like receivers, and (as noted
// above) member resolution for such receivers never falls through to user-declared candidates --
// so a 1-arg overload here would be an uncallable, misleading declaration. Widening that arity
// allow-list is dispatch-wiring work, not a Kotlin-source migration.

// MARK: - IntRange

public fun IntRange.forEach(action: (Int) -> Unit) {
    for (x in this) { action(x) }
}

public fun <R> IntRange.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    for (x in this) { result.add(transform(x)) }
    return result
}

public fun IntRange.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (x in this) { if (predicate(x)) result.add(x) }
    return result
}

public fun IntRange.toList(): List<Int> {
    val result = mutableListOf<Int>()
    for (x in this) { result.add(x) }
    return result
}

public fun IntRange.count(): Int {
    var count = 0
    for (x in this) { count += 1 }
    return count
}

// MARK: - IntProgression

public fun IntProgression.forEach(action: (Int) -> Unit) {
    for (x in this) { action(x) }
}

public fun <R> IntProgression.map(transform: (Int) -> R): List<R> {
    val result = mutableListOf<R>()
    for (x in this) { result.add(transform(x)) }
    return result
}

public fun IntProgression.filter(predicate: (Int) -> Boolean): List<Int> {
    val result = mutableListOf<Int>()
    for (x in this) { if (predicate(x)) result.add(x) }
    return result
}

public fun IntProgression.toList(): List<Int> {
    val result = mutableListOf<Int>()
    for (x in this) { result.add(x) }
    return result
}

public fun IntProgression.count(): Int {
    var count = 0
    for (x in this) { count += 1 }
    return count
}

// MARK: - LongRange

public fun LongRange.forEach(action: (Long) -> Unit) {
    for (x in this) { action(x) }
}

public fun <R> LongRange.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    for (x in this) { result.add(transform(x)) }
    return result
}

public fun LongRange.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    for (x in this) { if (predicate(x)) result.add(x) }
    return result
}

public fun LongRange.toList(): List<Long> {
    val result = mutableListOf<Long>()
    for (x in this) { result.add(x) }
    return result
}

public fun LongRange.count(): Int {
    var count = 0
    for (x in this) { count += 1 }
    return count
}

// MARK: - LongProgression

public fun LongProgression.forEach(action: (Long) -> Unit) {
    for (x in this) { action(x) }
}

public fun <R> LongProgression.map(transform: (Long) -> R): List<R> {
    val result = mutableListOf<R>()
    for (x in this) { result.add(transform(x)) }
    return result
}

public fun LongProgression.filter(predicate: (Long) -> Boolean): List<Long> {
    val result = mutableListOf<Long>()
    for (x in this) { if (predicate(x)) result.add(x) }
    return result
}

public fun LongProgression.toList(): List<Long> {
    val result = mutableListOf<Long>()
    for (x in this) { result.add(x) }
    return result
}

public fun LongProgression.count(): Int {
    var count = 0
    for (x in this) { count += 1 }
    return count
}

// MARK: - CharRange

public fun CharRange.forEach(action: (Char) -> Unit) {
    for (x in this) { action(x) }
}

public fun <R> CharRange.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    for (x in this) { result.add(transform(x)) }
    return result
}

public fun CharRange.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    for (x in this) { if (predicate(x)) result.add(x) }
    return result
}

public fun CharRange.toList(): List<Char> {
    val result = mutableListOf<Char>()
    for (x in this) { result.add(x) }
    return result
}

public fun CharRange.count(): Int {
    var count = 0
    for (x in this) { count += 1 }
    return count
}

// MARK: - CharProgression

public fun CharProgression.forEach(action: (Char) -> Unit) {
    for (x in this) { action(x) }
}

public fun <R> CharProgression.map(transform: (Char) -> R): List<R> {
    val result = mutableListOf<R>()
    for (x in this) { result.add(transform(x)) }
    return result
}

public fun CharProgression.filter(predicate: (Char) -> Boolean): List<Char> {
    val result = mutableListOf<Char>()
    for (x in this) { if (predicate(x)) result.add(x) }
    return result
}

public fun CharProgression.toList(): List<Char> {
    val result = mutableListOf<Char>()
    for (x in this) { result.add(x) }
    return result
}

public fun CharProgression.count(): Int {
    var count = 0
    for (x in this) { count += 1 }
    return count
}
