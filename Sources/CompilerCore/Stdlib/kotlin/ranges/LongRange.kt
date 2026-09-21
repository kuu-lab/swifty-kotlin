/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-708: The typed range shell is source-backed; construction retains only
// the hidden runtime factory for the range handle.
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

    public companion object {}
}
