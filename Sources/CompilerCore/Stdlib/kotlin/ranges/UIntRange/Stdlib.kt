/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1314: UIntRange owns its public constructor and Companion object in
// bundled Kotlin source. The range payload remains a runtime-managed unsigned
// range handle, so construction retains the existing ABI factory.
// `equals`/`hashCode`/`toString` are declared here as real members (matching
// Kotlin's UIntRange): member dispatch on this final class stays static, so
// calls don't fall through to virtual UIntProgression slots the runtime
// range handle's vtable doesn't have.
public class UIntRange @KsSymbolName("__kk_uint_rangeTo") constructor(
    start: UInt,
    endInclusive: UInt,
) : UIntProgression(start, endInclusive, 1), ClosedRange<UInt>, OpenEndRange<UInt> {
    public override val start: UInt get() = first
    public override val endInclusive: UInt get() = last

    public override val endExclusive: UInt
        get() {
            if (last == UInt.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1u
        }

    public override fun isEmpty(): Boolean = first > last

    public override fun equals(other: Any?): Boolean =
        other is UIntRange && (isEmpty() && other.isEmpty() || first == other.first && last == other.last)

    public override fun hashCode(): Int =
        if (isEmpty()) -1 else 31 * first.toInt() + last.toInt()

    public override fun toString(): String = "$first..$last"

    public companion object {}
}
