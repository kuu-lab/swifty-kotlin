/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines `Channel.kt`.
 */

package kotlinx.coroutines.channels

// KSP-1573: strategy for a `send`/`trySend` when the channel buffer is full.
// Pure Kotlin enum; the ordinal is the value passed across the
// `__kk_channel_create_with_policy` ABI boundary.
public enum class BufferOverflow {
    /** Suspend on buffer overflow (default rendezvous/buffered semantics). */
    SUSPEND,

    /** Drop the oldest buffered value to make room for the new one. */
    DROP_OLDEST,

    /** Drop the value that is being sent right now. */
    DROP_LATEST,
}
