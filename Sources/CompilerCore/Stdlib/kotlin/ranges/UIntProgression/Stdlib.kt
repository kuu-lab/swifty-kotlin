/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

// KSP-1312: Keep the UIntProgression nominal and its Companion source-backed.
// Runtime-backed members remain synthetic until their dedicated migrations.
public open class UIntProgression internal constructor(
    start: UInt,
    endInclusive: UInt,
    step: Int,
) : Iterable<UInt> {
    public companion object {}
}
