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
// `trySend` returns the bundled `ChannelResult` value class, which wraps the
// tagged Int token produced by `__kk_channel_try_send`; `close(cause)` bridges
// to `__kk_channel_close_cause`, which retains the first close cause in the
// runtime handle.

public interface SendChannel<in E> {
    @KsSymbolName("kk_channel_send")
    public external suspend fun send(element: E): Unit

    @KsSymbolName("__kk_channel_try_send")
    public external fun trySend(element: E): ChannelResult<Unit>

    @KsSymbolName("kk_channel_close")
    public external fun close(): Boolean

    @KsSymbolName("__kk_channel_close_cause")
    public external fun close(cause: Throwable?): Boolean
}

// ---- Residual runtime bridges for `Channel` receivers (the synthetic
// `Channel` class does not declare the `SendChannel` supertype here, so the
// `Channel`-receiver surface is provided through extensions below).

@KsSymbolName("__kk_channel_try_send")
private external fun Channel<*>.__kkChannelTrySend(element: Any?): Int

@KsSymbolName("__kk_channel_close_cause")
private external fun Channel<*>.__kkChannelCloseCause(cause: Throwable?): Int

@KsSymbolName("kk_channel_is_closed_for_send")
private external fun SendChannel<*>.__kkSendChannelIsClosedForSend(): Int

@KsSymbolName("kk_channel_is_empty")
private external fun Channel<*>.__kkChannelIsEmpty(): Int

// ---- trySend on Channel receivers. `SendChannel.trySend` is an `external`
// member (see the interface above); a `Channel`-receiver extension provides
// the same surface.

/**
 * Sends the specified [element] to this channel without suspending, returning
 * a [ChannelResult] that indicates whether the operation succeeded.
 */
public fun <E> Channel<E>.trySend(element: E): ChannelResult<Unit> =
    ChannelResult<Unit>(this.__kkChannelTrySend(element))

// ---- close(cause) on Channel receivers (SendChannel variant is a member).

/**
 * Closes this channel with an optional [cause], matching upstream
 * `SendChannel.close(cause: Throwable?): Boolean`. The cause is retained by
 * the runtime and surfaced through [ChannelResult.exceptionOrNull].
 */
public fun Channel<*>.close(cause: Throwable?): Boolean =
    this.__kkChannelCloseCause(cause) != 0

// ---- Closed-state queries

/**
 * Whether this channel was closed for sending. Extension properties use a
 * star-projected receiver because the parser does not accept type parameters
 * on extension properties.
 */
public val SendChannel<*>.isClosedForSend: Boolean
    get() = this.__kkSendChannelIsClosedForSend() != 0

/**
 * Whether the channel currently has no receivable element (empty buffer and
 * no suspended sender). Matches upstream `ReceiveChannel.isEmpty`; the
 * `Channel<*>` receiver covers `ReceiveChannel` through its type alias.
 */
public val Channel<*>.isEmpty: Boolean
    get() = this.__kkChannelIsEmpty() != 0

// ---- cancel / consume

/**
 * Cancels this channel with an optional [cause]. Matches upstream
 * `ReceiveChannel.cancel`: closes the channel for new elements and, when no
 * cause is given, substitutes a default `CancellationException`.
 */
public fun Channel<*>.cancel(cause: CancellationException? = null): Unit {
    this.__kkChannelCloseCause(cause ?: CancellationException())
}

/**
 * Executes the given [block] and [cancels][cancel] the channel afterward.
 * Mirrors upstream `ReceiveChannel.consume`.
 */
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

/**
 * Performs the given [action] for each received element and cancels the
 * channel afterward. Mirrors upstream `ReceiveChannel.consumeEach`.
 */
public suspend fun <E> Channel<E>.consumeEach(action: (E) -> Unit) {
    consume {
        for (element in this) {
            action(element as E)
        }
    }
}

/**
 * Internal helper: cancels the channel after a [consume] block finished,
 * wrapping a consumer failure in a `CancellationException` like upstream's
 * `cancelConsumed`.
 */
internal fun Channel<*>.cancelConsumed(cause: Throwable?) {
    this.cancel(
        if (cause == null) null
        else if (cause is CancellationException) cause as CancellationException
        else CancellationException("Channel was consumed, consumer had failed", cause)
    )
}

// ---- Terminal exceptions (upstream: bottom of Channel.kt)

/**
 * Thrown when trying to send to a channel that was closed normally.
 */
public class ClosedSendChannelException(message: String) : IllegalStateException(message)

/**
 * Thrown when trying to receive from a channel that was closed normally.
 */
public class ClosedReceiveChannelException(message: String) : NoSuchElementException(message)
