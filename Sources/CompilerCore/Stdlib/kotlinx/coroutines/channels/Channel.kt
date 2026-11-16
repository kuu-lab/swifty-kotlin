/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core common/src/channels/Channel.kt and
 * Channels.common.kt.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName
import kotlin.coroutines.cancellation.CancellationException

// KSP-1571: SendChannel moved here from ProducerScope.kt to match the upstream
// file layout (SendChannel lives in Channel.kt upstream). The member
// operations stay external — the runtime channel handle is the receiver
// itself, so each member bridges straight to a `kk_channel_*` entry point.
//
// `close(cause)` bridges to `__kk_channel_close_cause`, which retains the
// first close cause in the runtime handle.

public interface SendChannel<in E> {
    @KsSymbolName("kk_channel_send")
    public external suspend fun send(element: E): Unit

    @KsSymbolName("__kk_channel_try_send")
    public external fun trySend(element: E): ChannelResult<Unit>

    @KsSymbolName("kk_channel_close")
    public external fun close(): Boolean

    @KsSymbolName("__kk_channel_close_cause")
    public external fun close(cause: Throwable?): Boolean

    @KsSymbolName("kk_channel_is_closed_for_send")
    public val isClosedForSend: Boolean
}

// KUU-4072: upstream declares `public interface Channel<E> : SendChannel<E>,
// ReceiveChannel<E>`. `ReceiveChannel` remains a type alias to `Channel` in
// this runtime, so the source supertype list names `SendChannel` only; the
// members below carry the upstream `ReceiveChannel` surface. Every member
// bridges to the same `kk_channel_*` entry point the former top-level
// extensions used — raw channel handles have no Kotlin itable, so member
// calls must keep resolving to direct external calls — while user
// implementations and `by`-delegation can now override them.
public interface Channel<E> : SendChannel<E> {
    @KsSymbolName("__kk_channel_try_receive")
    public fun tryReceive(): ChannelResult<E>

    @KsSymbolName("__kk_channel_receive_catching")
    public suspend fun receiveCatching(): ChannelResult<E>

    // Upstream `cancel(cause: CancellationException? = null)`: bare
    // `cancel()` installs the default `CancellationException("Channel was
    // cancelled")` close cause, matching `cancel(null)` — raw channel handles
    // have no itable, so both members must stay direct external calls.
    @KsSymbolName("__kk_channel_cancel")
    public fun cancel()

    @KsSymbolName("__kk_channel_cancel_with_cause")
    public fun cancel(cause: CancellationException?)

    @KsSymbolName("kk_channel_is_closed_for_receive")
    public val isClosedForReceive: Boolean

    @KsSymbolName("kk_channel_is_empty")
    public val isEmpty: Boolean
}

@KsSymbolName("__kk_channel_invoke_on_close")
private external fun __kkChannelInvokeOnClose(channel: Any, handler: (cause: Throwable?) -> Unit): Int

public fun SendChannel<*>.invokeOnClose(handler: (cause: Throwable?) -> Unit) {
    __kkChannelInvokeOnClose(this, handler)
}

public fun Channel<*>.invokeOnClose(handler: (cause: Throwable?) -> Unit) {
    __kkChannelInvokeOnClose(this, handler)
}

public fun <E, R> Channel<E>.consume(block: Channel<E>.() -> R): R {
    var cause: Throwable? = null
    try {
        return block(this)
    } catch (e: Throwable) {
        cause = e
        throw e
    } finally {
        this.cancelConsumed(cause)
    }
}

public suspend fun <E> Channel<E>.consumeEach(action: (E) -> Unit) {
    consume {
        for (element in this) {
            action(element as E)
        }
    }
}

internal fun Channel<*>.cancelConsumed(cause: Throwable?) {
    this.cancel(
        if (cause == null) null
        else if (cause is CancellationException) cause as CancellationException
        else CancellationException("Channel was consumed, consumer had failed", cause)
    )
}

// `Channel.Factory` capacity constants (RENDEZVOUS / UNLIMITED / CONFLATED /
// BUFFERED / OPTIONAL_CHANNEL) live as extension properties on the synthetic
// `Channel.Factory` companion anchor. The two-argument factory overload below
// forwards both the capacity and the overflow policy to the runtime through
// `__kk_channel_create_with_policy` so a single constructor call can express
// every kotlinx Channel(capacity, onBufferOverflow) shape.

@KsSymbolName("__kk_channel_create_with_policy")
private external fun <T> __kkChannelCreateWithPolicy(capacity: Int, onBufferOverflow: Int): Channel<T>

public fun <T> Channel(capacity: Int, onBufferOverflow: BufferOverflow): Channel<T> {
    require(capacity >= -2) { "Invalid channel capacity: $capacity, should be >=0" }
    require(capacity != -1 /* CONFLATED */ || onBufferOverflow == BufferOverflow.SUSPEND) {
        "CONFLATED capacity cannot be used with non-default onBufferOverflow"
    }
    return __kkChannelCreateWithPolicy(capacity, onBufferOverflow.ordinal)
}

public val Channel.Factory.RENDEZVOUS: Int
    get() = 0

public val Channel.Factory.UNLIMITED: Int
    get() = Int.MAX_VALUE

public val Channel.Factory.CONFLATED: Int
    get() = -1

public val Channel.Factory.BUFFERED: Int
    get() = -2

// Upstream declares OPTIONAL_CHANNEL as `internal` ("only for internal use,
// cannot be used with Channel(...)"): internal builders normalize it to
// BUFFERED before allocating a channel (ChannelFlow.produceCapacity), and the
// public factories reject the raw -3 sentinel with IllegalArgumentException.
internal val Channel.Factory.OPTIONAL_CHANNEL: Int
    get() = -3

// `receiveOrNull` stays an extension (upstream shape): it is a convenience
// wrapper over the `receiveCatching` member and is not part of the
// overridable surface Turbine-style wrappers rely on.
public suspend fun <E> ReceiveChannel<E>.receiveOrNull(): E? =
    receiveCatching().getOrNull()
