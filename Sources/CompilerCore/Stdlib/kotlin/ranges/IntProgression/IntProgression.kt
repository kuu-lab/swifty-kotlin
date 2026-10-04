/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

public open class IntProgression internal constructor(
    start: Int,
    endInclusive: Int,
    step: Int,
) : Iterable<Int> {
    init {
        if (step == 0) throw IllegalArgumentException("Step must be non-zero.")
        if (step == Int.MIN_VALUE) {
            throw IllegalArgumentException("Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        }
    }

    public val first: Int
        get() = intProgressionFirst(this)

    public val last: Int
        get() = intProgressionLast(this)

    public val step: Int
        get() = intProgressionStep(this)

    public override operator fun iterator(): IntIterator =
        IntProgressionIterator(first, last, step)

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is IntProgression) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last && step == other.step
    }

    public override fun hashCode(): Int =
        if (isEmpty()) -1 else 31 * (31 * first + last) + step

    public override fun toString(): String =
        if (step > 0) "$first..$last step $step"
        else "$first downTo $last step ${-step}"

    public companion object {}
}

@KsSymbolName("__kk_range_first")
private external fun intProgressionFirst(progression: IntProgression): Int

@KsSymbolName("__kk_range_last")
private external fun intProgressionLast(progression: IntProgression): Int

@KsSymbolName("kk_range_step")
private external fun intProgressionStep(progression: IntProgression): Int
