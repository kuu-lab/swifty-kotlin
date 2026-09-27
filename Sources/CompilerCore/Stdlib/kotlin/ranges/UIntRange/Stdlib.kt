/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1314: UIntRange owns its public constructor and Companion object in
// bundled Kotlin source. The range payload remains a runtime-managed unsigned
// range handle, so construction retains the existing ABI factory.
// Receiver members remain residual synthetic/runtime-backed APIs for KSP-1315.
public class UIntRange @KsSymbolName("__kk_uint_rangeTo") constructor(
    start: UInt,
    endInclusive: UInt,
) : UIntProgression(start, endInclusive, 1), ClosedRange<UInt>, OpenEndRange<UInt> {
    public companion object {}
}
