/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

// KSP-1317: Keep the ULongProgression nominal and its Companion source-backed.
// Runtime-backed members remain synthetic until their dedicated migrations.
public open class ULongProgression internal constructor(
    start: ULong,
    endInclusive: ULong,
    step: Long,
) : Iterable<ULong> {
    public companion object {}
}
