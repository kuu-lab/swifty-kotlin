/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1281: UIntRange owns its public constructor and Companion object in
// bundled Kotlin source. The range payload remains a runtime-managed unsigned
// range handle, so construction retains the existing ABI factory (the same
// treatment as ULongRange in KSP-1320).
// Receiver members remain residual synthetic/runtime-backed APIs for KSP-1315,
// except `toString`, which is declared here because inheriting
// `UIntProgression.toString` would print the progression form
// (`"$first..$last step $step"`) instead of the range form `"$start..$endInclusive"`.
// (`equals`/`hashCode` stay inherited: the upstream overrides need `other is UIntRange`,
// and `is` checks do not recognize runtime range boxes.)
public class UIntRange @KsSymbolName("__kk_uint_rangeTo") constructor(
    start: UInt,
    endInclusive: UInt,
) : UIntProgression(start, endInclusive, 1), ClosedRange<UInt>, OpenEndRange<UInt> {
    public override fun toString(): String = "$first..$last"

    public companion object {}
}
