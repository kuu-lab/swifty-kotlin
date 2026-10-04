/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1306: Keep LongProgression's public receiver members source-backed on
// the KSP-1305 nominal shell. The runtime progression box still owns the
// element bounds, so `first`/`last`/`step` delegate to the shared
// __kk_range_* / __kk_long_range_step bridges. Companion.fromClosedRange stays
// synthetic until KSP-1307.
public open class LongProgression internal constructor(
    start: Long,
    endInclusive: Long,
    step: Long,
) : Iterable<Long> {
    init {
        if (step == 0L) throw IllegalArgumentException("Step must be non-zero.")
        if (step == Long.MIN_VALUE) {
            throw IllegalArgumentException("Step must be greater than Long.MIN_VALUE to avoid overflow on negation.")
        }
    }

    public val first: Long
        get() = longProgressionFirst(this)

    public val last: Long
        get() = longProgressionLast(this)

    public val step: Long
        get() = longProgressionStep(this)

    public override operator fun iterator(): LongIterator =
        LongProgressionIterator(first, last, step)

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is LongProgression) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last && step == other.step
    }

    public override fun hashCode(): Int {
        if (isEmpty()) return -1
        return 31 * (31 * first.hashCode() + last.hashCode()) + step.hashCode()
    }

    public override fun toString(): String =
        if (step > 0L) "$first..$last step $step"
        else "$first downTo $last step ${-step}"

    public companion object {}
}

@KsSymbolName("__kk_range_first")
private external fun longProgressionFirst(progression: LongProgression): Long

@KsSymbolName("__kk_range_last")
private external fun longProgressionLast(progression: LongProgression): Long

@KsSymbolName("__kk_long_range_step")
private external fun longProgressionStep(progression: LongProgression): Long
