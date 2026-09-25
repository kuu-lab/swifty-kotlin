/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1313: Keep UIntProgression's public receiver members source-backed.
public open class UIntProgression internal constructor(
    start: UInt,
    endInclusive: UInt,
    step: Int,
) : Iterable<UInt> {
    init {
        if (step == 0) throw IllegalArgumentException("Step must be non-zero.")
        if (step == Int.MIN_VALUE) {
            throw IllegalArgumentException("Step must be greater than Int.MIN_VALUE to avoid overflow on negation.")
        }
    }

    public val first: UInt
        get() = uintProgressionFirst(this)

    public val last: UInt
        get() = uintProgressionLast(this)

    public val step: Int
        get() = uintProgressionStep(this)

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is UIntProgression) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last && step == other.step
    }

    public override fun hashCode(): Int {
        if (isEmpty()) return -1
        return 31 * (31 * first.hashCode() + last.hashCode()) + step
    }

    public override fun toString(): String =
        if (step > 0) "$first..$last step $step"
        else "$first downTo $last step ${-step.toLong()}"

    public companion object {}
}

@KsSymbolName("__kk_range_first")
private external fun uintProgressionFirst(progression: UIntProgression): UInt

@KsSymbolName("__kk_range_last")
private external fun uintProgressionLast(progression: UIntProgression): UInt

@KsSymbolName("kk_uint_range_step")
private external fun uintProgressionStep(progression: UIntProgression): Int
