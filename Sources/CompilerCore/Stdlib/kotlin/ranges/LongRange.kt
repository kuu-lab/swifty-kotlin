/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-708: The typed range shell is source-backed; construction retains only
// the hidden runtime factory for the range handle.
// KSP-1309: equals/hashCode/toString are source-backed member overrides on the
// class body so `==` and virtual dispatch resolve to the range members.
public class LongRange @KsSymbolName("__kk_long_rangeTo") constructor(
    start: Long,
    endInclusive: Long,
) : LongProgression(start, endInclusive, 1L), ClosedRange<Long>, OpenEndRange<Long> {
    public override val start: Long get() = first
    public override val endInclusive: Long get() = last
    public override val endExclusive: Long
        get() {
            if (last == Long.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1L
        }
    public override fun isEmpty(): Boolean = first > last

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is LongRange) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last
    }

    public override fun hashCode(): Int =
        if (isEmpty()) -1 else 31 * first.hashCode() + last.hashCode()

    public override fun toString(): String = "$first..$last"

    public companion object {}
}
