/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core common/src/channels/Channel.kt (ChannelResult).
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.InternalCoroutinesApi

// KSP-1571/KSP-1572: ChannelResult is an opaque runtime box (operation status
// plus the received element and the retained close cause) produced by the
// `__kk_channel_*` bridges, mirroring how kotlin.Result wraps
// RuntimeResultBox. The box is registered under this class's nominal type id,
// so it flows through the ABI as a `ChannelResult` instance directly.

@KsSymbolName("__kk_channel_result_status")
private external fun __kkChannelResultStatus(result: Any?): Int

@KsSymbolName("__kk_channel_result_value_or_null")
private external fun <T> __kkChannelResultValueOrNull(result: ChannelResult<T>): T?

@KsSymbolName("__kk_channel_result_get_or_throw")
private external fun <T> __kkChannelResultGetOrThrow(result: ChannelResult<T>): T

@KsSymbolName("__kk_channel_result_cause")
private external fun __kkChannelResultCause(result: Any?): Throwable?

// `value` is `Any?` so a single bridge serves success/closed/failed makers;
// boxed primitive elements unbox again at `as T` on the way out.
@KsSymbolName("__kk_channel_result_create")
private external fun <T> __kkChannelResultCreate(status: Int, value: Any?, cause: Throwable?): ChannelResult<T>

// Status codes mirror ChannelOperationStatus: 0 success, 1 closed,
// 2 cancelled, 3 failed.
private const val KK_CHANNEL_RESULT_STATUS_SUCCESS: Int = 0
private const val KK_CHANNEL_RESULT_STATUS_CLOSED: Int = 1
private const val KK_CHANNEL_RESULT_STATUS_CANCELLED: Int = 2
private const val KK_CHANNEL_RESULT_STATUS_FAILED: Int = 3

public class ChannelResult<out T> private constructor() {

    public val isSuccess: Boolean
        get() = __kkChannelResultStatus(this) == KK_CHANNEL_RESULT_STATUS_SUCCESS

    public val isFailure: Boolean
        get() = !isSuccess

    public val isClosed: Boolean
        get() {
            val status = __kkChannelResultStatus(this)
            return status == KK_CHANNEL_RESULT_STATUS_CLOSED || status == KK_CHANNEL_RESULT_STATUS_CANCELLED
        }

    public fun getOrThrow(): T =
        __kkChannelResultGetOrThrow(this)

    public fun getOrNull(): T? =
        __kkChannelResultValueOrNull(this)

    public fun exceptionOrNull(): Throwable? =
        __kkChannelResultCause(this)

    public companion object {
        @InternalCoroutinesApi
        public fun <T> success(value: T): ChannelResult<T> =
            __kkChannelResultCreate(KK_CHANNEL_RESULT_STATUS_SUCCESS, value, null)

        @InternalCoroutinesApi
        public fun <T> failure(): ChannelResult<T> =
            __kkChannelResultCreate(KK_CHANNEL_RESULT_STATUS_FAILED, null, null)

        @InternalCoroutinesApi
        public fun <T> closed(cause: Throwable?): ChannelResult<T> =
            __kkChannelResultCreate(KK_CHANNEL_RESULT_STATUS_CLOSED, null, cause)
    }

    public override fun toString(): String {
        if (isClosed) {
            return "Closed(${exceptionOrNull()})"
        }
        if (isFailure) {
            // Upstream's generic failure holds the `Failed` singleton as its
            // value, so it prints as `Value(Failed)`.
            return "Value(Failed)"
        }
        return "Value(${getOrNull()})"
    }
}

public inline fun <T> ChannelResult<T>.getOrElse(onFailure: (exception: Throwable?) -> T): T {
    return if (isSuccess) getOrThrow() else onFailure(exceptionOrNull())
}

public inline fun <T> ChannelResult<T>.onSuccess(action: (value: T) -> Unit): ChannelResult<T> {
    if (isSuccess) action(getOrThrow())
    return this
}

public inline fun <T> ChannelResult<T>.onFailure(action: (exception: Throwable?) -> Unit): ChannelResult<T> {
    if (isFailure) action(exceptionOrNull())
    return this
}

public inline fun <T> ChannelResult<T>.onClosed(action: (exception: Throwable?) -> Unit): ChannelResult<T> {
    if (isClosed) action(exceptionOrNull())
    return this
}

/**
 * Mirrors upstream `holdsValue`, which is `holder === success` on the JVM — a
 * success result in the box model.
 */
internal val ChannelResult<*>.holdsValue: Boolean
    get() = isSuccess
