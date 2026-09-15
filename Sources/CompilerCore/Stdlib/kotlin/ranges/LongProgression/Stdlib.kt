/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

// KSP-1305: Keep the LongProgression nominal and its Companion source-backed,
// mirroring the IntProgression shell from KSP-1300.
// Runtime-backed members remain synthetic until their dedicated migrations
// (KSP-1306 for the receiver member surface, KSP-1307 for
// Companion.fromClosedRange).
public open class LongProgression internal constructor(
    start: Long,
    endInclusive: Long,
    step: Long,
) : Iterable<Long> {
    public companion object {}
}
