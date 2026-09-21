/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-708: The typed range shell is source-backed; construction retains only
// the hidden runtime factory for the range handle.
public class CharRange @KsSymbolName("__kk_char_rangeTo") constructor(
    start: Char,
    endInclusive: Char,
) : CharProgression(start, endInclusive, 1), ClosedRange<Char>, OpenEndRange<Char> {
    public override val start: Char get() = first
    public override val endInclusive: Char get() = last
    public override val endExclusive: Char
        get() {
            if (last == Char.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1
        }
    public override fun isEmpty(): Boolean = first > last

    public companion object {}
}
