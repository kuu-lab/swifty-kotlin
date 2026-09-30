/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1320/KSP-1321: ULongRange owns its public constructor, open-end
// properties, and value semantics in bundled Kotlin source. The range payload
// remains a runtime-managed unsigned range handle, so construction retains the
// existing ABI factory.
public class ULongRange @KsSymbolName("__kk_ulong_rangeTo") constructor(
    start: ULong,
    endInclusive: ULong,
) : ULongProgression(start, endInclusive, 1L), ClosedRange<ULong>, OpenEndRange<ULong> {
    public override val endInclusive: ULong get() = last

    public override val endExclusive: ULong
        get() {
            if (last == ULong.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1uL
        }

    public override fun isEmpty(): Boolean = first > last

    public override fun equals(other: Any?): Boolean =
        other is ULongRange && (isEmpty() && other.isEmpty() || first == other.first && last == other.last)

    public override fun hashCode(): Int =
        if (isEmpty()) -1 else 31 * (first xor (first shr 32)).toInt() + (last xor (last shr 32)).toInt()

    public override fun toString(): String = "$first..$last"

    public companion object {}
}
