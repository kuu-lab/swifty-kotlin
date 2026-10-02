/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-708: Keep the typed range shell in bundled Kotlin source. The signed
// range operator still uses the shared operator-core ABI.
// KSP-1303: equals/hashCode/toString are members so `==` and erased virtual
// dispatch use the range value rather than Any's identity behavior.
public class IntRange @KsSymbolName("kk_op_rangeTo") constructor(
    start: Int,
    endInclusive: Int,
) : IntProgression(start, endInclusive, 1), ClosedRange<Int>, OpenEndRange<Int> {
    public override val start: Int get() = first
    public override val endInclusive: Int get() = last
    public override val endExclusive: Int
        get() {
            if (last == Int.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1
        }
    public override fun isEmpty(): Boolean = first > last

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is IntRange) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last
    }

    public override fun hashCode(): Int =
        if (isEmpty()) -1 else 31 * first + last

    public override fun toString(): String = "$first..$last"

    public companion object {}
}
