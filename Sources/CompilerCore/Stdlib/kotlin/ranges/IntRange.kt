/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-708: Keep the typed range shell in bundled Kotlin source. The signed
// range operator still uses the shared operator-core ABI.
public class IntRange @KsSymbolName("kk_op_rangeTo") constructor(
    start: Int,
    endInclusive: Int,
) : IntProgression(start, endInclusive, 1), ClosedRange<Int>, OpenEndRange<Int> {
    public override val start: Int get() = first
    public override val endInclusive: Int get() = last
    public override val endExclusive: Int
        get() {
            if (last == Int.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return last + 1
        }
    public override fun isEmpty(): Boolean = first > last

    public companion object {}
}
