/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines channel builder APIs.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope

// KSP-1543: ProducerScope is the receiver exposed by channelFlow and
// callbackFlow. The object is backed by the runtime channel created for each
// collection; the member operations keep the public Kotlin shape while
// retaining the channel ABI at the boundary.
//
// KSP-1571: `SendChannel` moved to Channel.kt and `ChannelResult` to
// ChannelResult.kt to match the upstream file layout.

// KSP-1573: `ProducerScope.channel` returns the very handle the scope is
// backed by — the receiver handed to the launched block is the channel
// handle itself. ProducerScope stays a class so `channel` resolves through
// static member dispatch; an interface member getter would emit a virtual
// call the raw handle cannot serve.
@KsSymbolName("__kk_identity")
private external fun <E> __kkProducerScopeChannel(scope: ProducerScope<E>): SendChannel<E>

public class ProducerScope<out E> : CoroutineScope, SendChannel<E> {
    /** A reference to the channel this coroutine sends elements to. */
    public val channel: SendChannel<E>
        get() = __kkProducerScopeChannel(this)
}
