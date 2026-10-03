/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines `Channel.kt`.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName

// KSP-1573: capacity semantics for Channel.
//
// `Channel.Factory` capacity constants (RENDEZVOUS / UNLIMITED / CONFLATED /
// BUFFERED / OPTIONAL_CHANNEL) live as extension properties on the synthetic
// `Channel.Factory` companion anchor registered in
// HeaderHelpers+SyntheticCoroutineRegistry.swift. The two-argument factory
// overload below forwards both the capacity and the overflow policy to the
// runtime through `__kk_channel_create_with_policy` so a single constructor
// call can express every kotlinx Channel(capacity, onBufferOverflow) shape.

@KsSymbolName("__kk_channel_create_with_policy")
private external fun <T> __kkChannelCreateWithPolicy(capacity: Int, onBufferOverflow: Int): Channel<T>

public fun <T> Channel(capacity: Int, onBufferOverflow: BufferOverflow): Channel<T> =
    __kkChannelCreateWithPolicy(capacity, onBufferOverflow.ordinal)

public val Channel.Factory.RENDEZVOUS: Int
    get() = 0

public val Channel.Factory.UNLIMITED: Int
    get() = Int.MAX_VALUE

public val Channel.Factory.CONFLATED: Int
    get() = -1

public val Channel.Factory.BUFFERED: Int
    get() = -2

public val Channel.Factory.OPTIONAL_CHANNEL: Int
    get() = -3

// `invokeOnClose` registers `handler` to run exactly once when the channel
// transitions to closed. The handler's Kotlin type `(Throwable?) -> Unit`
// crosses the external boundary as an (fnPtr, closureRaw) pair, the same
// function-value convention Job.invokeOnCompletion already uses.
@KsSymbolName("__kk_channel_invoke_on_close")
private external fun __kkChannelInvokeOnClose(channel: Any, handler: (cause: Throwable?) -> Unit): Int

public fun SendChannel<*>.invokeOnClose(handler: (cause: Throwable?) -> Unit) {
    __kkChannelInvokeOnClose(this, handler)
}

public fun Channel<*>.invokeOnClose(handler: (cause: Throwable?) -> Unit) {
    __kkChannelInvokeOnClose(this, handler)
}
