/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines channel builder APIs.
 */

package kotlinx.coroutines.channels

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope

// KSP-1543: ProducerScope is the receiver exposed by channelFlow and
// callbackFlow. The object is backed by the runtime channel created for each
// collection; the member operations below keep the public Kotlin shape while
// retaining the channel ABI at the boundary.

// KSP-1572: ChannelResult is an opaque runtime box (operation status plus the
// received element) produced by the __kk_channel_* bridges, mirroring how
// kotlin.Result wraps RuntimeResultBox. Instances are only created by the
// runtime; the accessors below read the box back out.
@KsSymbolName("__kk_channel_result_status")
private external fun __kkChannelResultStatus(result: Any?): Int

@KsSymbolName("__kk_channel_result_value_or_null")
private external fun <T> __kkChannelResultValueOrNull(result: ChannelResult<T>): T?

@KsSymbolName("__kk_channel_result_get_or_throw")
private external fun <T> __kkChannelResultGetOrThrow(result: ChannelResult<T>): T

public class ChannelResult<out T> private constructor() {
    // Status codes mirror ChannelOperationStatus: 0 success, 1 closed,
    // 2 cancelled, 3 failed.
    public val isSuccess: Boolean
        get() = __kkChannelResultStatus(this) == 0

    public val isFailure: Boolean
        get() = !isSuccess

    public val isClosed: Boolean
        get() = __kkChannelResultStatus(this) == 1 || __kkChannelResultStatus(this) == 2

    public fun getOrNull(): T? =
        __kkChannelResultValueOrNull(this)

    public fun getOrThrow(): T =
        __kkChannelResultGetOrThrow(this)

    // No close causes yet: failure results carry no exception, matching
    // kotlinx's `exceptionOrNull` for results without a close cause.
    public fun exceptionOrNull(): Throwable? = null

    public companion object {}
}

public interface SendChannel<in E> {
    @KsSymbolName("kk_channel_send")
    public external suspend fun send(element: E): Unit

    @KsSymbolName("__kk_channel_try_send")
    public external fun trySend(element: E): ChannelResult<Unit>

    @KsSymbolName("kk_channel_close")
    public external fun close(): Boolean
}

// KSP-1573: `ProducerScope.channel` returns the very handle the scope is
// backed by — the receiver handed to the launched block is the channel
// handle itself. ProducerScope stays a class so `channel` resolves through
// static member dispatch; an interface member getter would emit a virtual
// call the raw handle cannot serve.
@KsSymbolName("__kk_identity")
private external fun <E> __kkProducerScopeChannel(scope: ProducerScope<E>): SendChannel<E>

@KsSymbolName("kk_coroutine_current_context")
private external fun __kkProducerScopeCurrentContext(): CoroutineContext

public class ProducerScope<out E> : CoroutineScope, SendChannel<E> {
    public override val coroutineContext: CoroutineContext
        get() = __kkProducerScopeCurrentContext()

    /** A reference to the channel this coroutine sends elements to. */
    public val channel: SendChannel<E>
        get() = __kkProducerScopeChannel(this)
}
