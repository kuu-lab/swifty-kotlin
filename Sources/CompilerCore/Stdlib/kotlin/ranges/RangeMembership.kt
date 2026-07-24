package kotlin.ranges

import kotlin.internal.KsSymbolName

// MIGRATION-RANGE-001
// contains(value) / isEmpty() for IntRange, LongRange, CharRange, IntProgression,
// LongProgression, CharProgression.
// Migration source: Sources/Runtime/RuntimeRangeAndDispatch.swift
//   (kk_range_contains, kk_range_isEmpty, kk_char_range_isEmpty, kk_op_contains)
//   Sources/Runtime/RuntimeRangeLongRange.swift
//   (kk_long_range_contains, kk_long_range_isEmpty)
// See RangeIterators.kt for the iterator() half of this migration.
//
// NOTE: KSP-312 wires explicit `contains`/`isEmpty` calls through bundled stdlib
// source and removes the duplicate CallTypeChecker+RangeMemberFallback entries.
// The existing synthetic class members are skipped when the bundled declaration
// index sees these extension signatures. `x in range` and `for (x in range)` are
// still special-cased in ExprLowerer+ControlFlowAndBlocks.swift; retiring that
// direct lowering path is intentionally left to KSP-452.
//
// These implementations are written purely in terms of the first/last/step
// properties every one of the six classes already exposes as Kotlin members.
//
// LongRange.step is Kotlin-typed Long (registerSyntheticLongRangeStub) while
// LongProgression.step is Kotlin-typed Int (registerSyntheticProgressionStub,
// shared stepType across all *Progression classes) — a pre-existing asymmetry in
// those registrations, not introduced here. The LongProgression overloads below
// widen step to Long before delegating so the shared helper only has to handle
// one width.

// Keep these helpers specialized: the generic Comparable helper makes bundled
// source type-checking fail to terminate even for unrelated small programs.
private fun rangeIsEmptyInt(first: Int, last: Int, step: Long): Boolean =
    if (step > 0L) first > last else if (step < 0L) first < last else true

private fun rangeIsEmptyLong(first: Long, last: Long, step: Long): Boolean =
    if (step > 0L) first > last else if (step < 0L) first < last else true

private fun rangeIsEmptyChar(first: Char, last: Char, step: Long): Boolean =
    if (step > 0L) first > last else if (step < 0L) first < last else true

@KsSymbolName("kk_range_isEmpty")
public fun IntRange.isEmpty(): Boolean = rangeIsEmptyInt(first, last, step.toLong())
public fun IntProgression.isEmpty(): Boolean = rangeIsEmptyInt(first, last, step.toLong())
public fun LongRange.isEmpty(): Boolean = rangeIsEmptyLong(first, last, step)
public fun LongProgression.isEmpty(): Boolean = rangeIsEmptyLong(first, last, step.toLong())
public fun CharRange.isEmpty(): Boolean = rangeIsEmptyChar(first, last, step.toLong())
public fun CharProgression.isEmpty(): Boolean = rangeIsEmptyChar(first, last, step.toLong())

// Widening the subtraction to Long (Int) / staying in Long (Long) keeps
// `value - first` from wrapping when first/value sit near Int.MIN_VALUE /
// Int.MAX_VALUE, mirroring the overflow guards kk_range_contains applies before
// its modulo check.
private fun containsInt(value: Int, first: Int, last: Int, step: Int): Boolean {
    if (step > 0) {
        if (value < first || value > last) return false
    } else if (step < 0) {
        if (value > first || value < last) return false
    } else {
        return false
    }
    return (value.toLong() - first.toLong()) % step.toLong() == 0L
}

private fun containsLong(value: Long, first: Long, last: Long, step: Long): Boolean {
    if (step > 0L) {
        if (value < first || value > last) return false
    } else if (step < 0L) {
        if (value > first || value < last) return false
    } else {
        return false
    }
    return (value - first) % step == 0L
}

private fun containsChar(value: Char, first: Char, last: Char, step: Int): Boolean {
    if (step > 0) {
        if (value < first || value > last) return false
    } else if (step < 0) {
        if (value > first || value < last) return false
    } else {
        return false
    }
    return (value - first) % step == 0
}

public operator fun IntRange.contains(value: Int): Boolean = containsInt(value, first, last, step)
public operator fun IntProgression.contains(value: Int): Boolean = containsInt(value, first, last, step)
public operator fun LongRange.contains(value: Long): Boolean = containsLong(value, first, last, step)
public operator fun LongProgression.contains(value: Long): Boolean =
    containsLong(value, first, last, step.toLong())
public operator fun CharRange.contains(value: Char): Boolean = containsChar(value, first, last, step)
public operator fun CharProgression.contains(value: Char): Boolean = containsChar(value, first, last, step)
