/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1320: ULongRange owns its public constructor and Companion object in
// bundled Kotlin source. The range payload remains a runtime-managed unsigned
// range handle, so construction retains the existing ABI factory.
// Receiver members remain residual synthetic/runtime-backed APIs for KSP-1321.
// KSP-1311: `OpenEndRange.endExclusive` is now a source-declared abstract
// member, so the class needs this override for abstract-member completeness.
// The declaration reuses the synthetic `endExclusive` member, which keeps its
// `__kk_range_endExclusive` external link — property reads still dispatch to
// the runtime bridge rather than running this getter body.
public class ULongRange @KsSymbolName("__kk_ulong_rangeTo") constructor(
    start: ULong,
    endInclusive: ULong,
) : ULongProgression(start, endInclusive, 1L), ClosedRange<ULong>, OpenEndRange<ULong> {
    public override val endExclusive: ULong
        get() {
            if (last == ULong.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1uL
        }

    public companion object {}
}
