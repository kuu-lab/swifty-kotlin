/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// The runtime progression handle owns the bounds and step; member getters
// reuse its shared bridges. Companion.fromClosedRange remains synthetic.
public open class CharProgression internal constructor(
    start: Char,
    endInclusive: Char,
    step: Int,
) : Iterable<Char> {
    public val first: Char
        get() = charProgressionFirst(this)

    public val last: Char
        get() = charProgressionLast(this)

    public val step: Int
        get() = charProgressionStep(this)

    public override operator fun iterator(): CharIterator =
        CharProgressionIterator(first, last, step)

    public override fun equals(other: Any?): Boolean {
        // Range handles have no vtable; preserve CharRange overrides after upcasting.
        if (this is CharRange) return (this as CharRange).equals(other)
        if (this === other) return true
        if (other !is CharProgression) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last && step == other.step
    }

    public override fun hashCode(): Int =
        if (this is CharRange) (this as CharRange).hashCode()
        else if (isEmpty()) -1 else 31 * (31 * first.hashCode() + last.hashCode()) + step

    public override fun toString(): String =
        if (this is CharRange) (this as CharRange).toString()
        else if (step > 0) "$first..$last step $step"
        else "$first downTo $last step ${-step}"

    public companion object {}
}

@KsSymbolName("__kk_range_first")
private external fun charProgressionFirst(progression: CharProgression): Char

@KsSymbolName("__kk_range_last")
private external fun charProgressionLast(progression: CharProgression): Char

@KsSymbolName("kk_range_step")
private external fun charProgressionStep(progression: CharProgression): Int
