/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// Progressions are opaque runtime range handles, so their source properties
// must read through the same bridges used by the other progression classes.

public open class ULongProgression internal constructor(
    start: ULong,
    endInclusive: ULong,
    step: Long,
) : Iterable<ULong> {
    init {
        if (step == 0L) throw IllegalArgumentException("Step must be non-zero.")
        if (step == Long.MIN_VALUE) {
            throw IllegalArgumentException("Step must be greater than Long.MIN_VALUE to avoid overflow on negation.")
        }
    }

    public val first: ULong
        get() = ulongProgressionFirst(this)

    public val last: ULong
        get() = ulongProgressionLast(this)

    public val step: Long
        get() = ulongProgressionStep(this)

    override fun equals(other: Any?): Boolean =
        other is ULongProgression && (isEmpty() && other.isEmpty() ||
            first == other.first && last == other.last && step == other.step)

    override fun hashCode(): Int = if (isEmpty()) {
        -1
    } else {
        val firstHash = (first xor (first shr 32)).toInt()
        val lastHash = (last xor (last shr 32)).toInt()
        val stepHash = (step xor (step ushr 32)).toInt()
        31 * (31 * firstHash + lastHash) + stepHash
    }

    override fun iterator(): Iterator<ULong> = ULongProgressionIterator(first, last, step)

    override fun toString(): String = if (step > 0) {
        "$first..$last step $step"
    } else {
        "$first downTo $last step ${-step}"
    }

    public companion object {}
}

@KsSymbolName("__kk_range_first")
private external fun ulongProgressionFirst(progression: ULongProgression): ULong

@KsSymbolName("__kk_range_last")
private external fun ulongProgressionLast(progression: ULongProgression): ULong

@KsSymbolName("__kk_ulong_range_step")
private external fun ulongProgressionStep(progression: ULongProgression): Long
