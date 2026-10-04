/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-708: The typed range shell is source-backed; construction retains only
// the hidden runtime factory for the range handle.
// KSP-1296: Range value semantics are source-backed member overrides.
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
    public override operator fun contains(value: Char): Boolean = value >= first && value <= last

    public override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CharRange) return false
        if (isEmpty()) return other.isEmpty()
        return first == other.first && last == other.last
    }

    public override fun hashCode(): Int =
        if (isEmpty()) -1 else 31 * first.hashCode() + last.hashCode()

    public override fun toString(): String = "$first..$last"

    public companion object {}
}
