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
public class ULongRange @KsSymbolName("kk_ulong_rangeTo") constructor(
    start: ULong,
    endInclusive: ULong,
) : ULongProgression(start, endInclusive, 1L), ClosedRange<ULong>, OpenEndRange<ULong> {
    public companion object {}
}
