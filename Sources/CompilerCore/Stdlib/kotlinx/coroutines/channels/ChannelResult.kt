/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core common/src/channels/Channel.kt (ChannelResult).
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName

// KSP-1571: ChannelResult is a `@JvmInline value class` over a single Int
// token so `SendChannel.trySend` can stay an `external` member — the residual
// `__kk_channel_try_send` bridge returns the token directly.  The token packs
// a 2-bit tag with a payload pointer:
//
//   token = (payload << 2) | tag
//   tag 0 = success (payload = element pointer, or the shared Unit box)
//   tag 1 = closed  (payload = retained close-cause `Throwable` pointer, or 0)
//   tag 2 = failed  (payload = 0)
//
// Pointer payloads are decoded/encoded by the `__kk_channel_result_*` bridges;
// pure tag checks are plain Kotlin bit operations on the token.

// ---- Residual runtime bridges (token codecs; receiver-free Int signatures).

@KsSymbolName("__kk_channel_result_value")
private external fun __kkChannelResultValue(token: Int): Any?

@KsSymbolName("__kk_channel_result_cause")
private external fun __kkChannelResultCause(token: Int): Throwable?

// The generic `value: T` keeps the element representation (raw Int for value
// types, object pointer for reference types) — an `Any?` parameter would box
// value types into a heap object and `as T` would leak the box pointer.
@KsSymbolName("__kk_channel_result_success")
private external fun <T> __kkChannelResultSuccess(value: T): Int

@KsSymbolName("__kk_channel_result_closed")
private external fun __kkChannelResultClosedToken(cause: Throwable?): Int

private const val KK_CHANNEL_RESULT_TAG_CLOSED: Int = 1
private const val KK_CHANNEL_RESULT_TAG_FAILED: Int = 2
// Closed with no retained cause: upstream `trySend` reports
// `closed(sendException)` where `sendException` substitutes
// `ClosedSendChannelException`, materialised here on read.
private const val KK_CHANNEL_RESULT_TAG_CLOSED_NO_CAUSE: Int = 3

/**
 * Result of a channel operation that either succeeded with a value or failed
 * with an optional close cause. Mirrors upstream `ChannelResult`.
 */
@JvmInline
public value class ChannelResult<out T> internal constructor(internal val token: Int) {

    /**
     * Whether the operation succeeded. See upstream docs for details.
     */
    public val isSuccess: Boolean
        get() = (token and 3) == 0

    /**
     * Whether the operation failed. A shorthand for `!isSuccess`.
     */
    public val isFailure: Boolean
        get() = (token and 3) != 0

    /**
     * Whether the operation failed because the channel was closed.
     */
    public val isClosed: Boolean
        get() {
            val tag = token and 3
            return tag == KK_CHANNEL_RESULT_TAG_CLOSED || tag == KK_CHANNEL_RESULT_TAG_CLOSED_NO_CAUSE
        }

    /**
     * Returns the encapsulated [T] if the operation succeeded, or throws the
     * encapsulated exception if it failed.
     */
    public fun getOrThrow(): T {
        val tag = token and 3
        if (tag == KK_CHANNEL_RESULT_TAG_CLOSED_NO_CAUSE) {
            throw ClosedSendChannelException("Channel was closed")
        }
        if (tag == KK_CHANNEL_RESULT_TAG_CLOSED) {
            // The decoded cause is a raw object pointer; a zero payload decodes
            // to a non-null zero pointer, so detect "no cause" from the token
            // payload rather than a null check on the decoded reference.
            if ((token ushr 2) != 0) {
                throw __kkChannelResultCause(token)!!
            }
            throw ClosedReceiveChannelException("Channel was closed")
        }
        if (isFailure) {
            error("Trying to call 'getOrThrow' on a failed channel result")
        }
        val value = __kkChannelResultValue(token)
        if (value == null) {
            error("Trying to call 'getOrThrow' on a successful result that carried no value")
        }
        return value as T
    }

    /**
     * Returns the encapsulated [T] if the operation succeeded, or `null` if it
     * failed.
     */
    public fun getOrNull(): T? {
        if (!isSuccess) {
            return null
        }
        val value = __kkChannelResultValue(token)
        if (value == null) {
            return null
        }
        return value as T
    }

    /**
     * Returns the exception with which the channel was closed, or `null` if
     * the channel was not closed or was closed without a cause.
     */
    public fun exceptionOrNull(): Throwable? {
        val tag = token and 3
        if (tag == KK_CHANNEL_RESULT_TAG_CLOSED_NO_CAUSE) {
            return ClosedSendChannelException("Channel was closed")
        }
        if (tag == KK_CHANNEL_RESULT_TAG_CLOSED && (token ushr 2) != 0) {
            return __kkChannelResultCause(token)
        }
        return null
    }

    public companion object {
        /**
         * Wraps [value] in a successful result.
         */
        public fun <T> success(value: T): ChannelResult<T> =
            ChannelResult<T>(__kkChannelResultSuccess<T>(value))

        /**
         * A failure without a close cause.
         */
        public fun <T> failure(): ChannelResult<T> = ChannelResult<T>(KK_CHANNEL_RESULT_TAG_FAILED)

        /**
         * A failure caused by channel closure with an optional [cause].
         */
        public fun <T> closed(cause: Throwable?): ChannelResult<T> =
            ChannelResult<T>(__kkChannelResultClosedToken(cause))
    }

    public override fun toString(): String {
        if (isClosed) {
            return "Closed(${exceptionOrNull()})"
        }
        if (isFailure) {
            return "Failed"
        }
        return "Value(${__kkChannelResultValue(token)})"
    }
}

/**
 * Returns the encapsulated value if the operation succeeded, or the result of
 * [onFailure] for [ChannelResult.exceptionOrNull] otherwise.
 */
public inline fun <T> ChannelResult<T>.getOrElse(onFailure: (exception: Throwable?) -> T): T {
    return if (isSuccess) getOrThrow() else onFailure(exceptionOrNull())
}

/**
 * Performs the given [action] on the encapsulated value if the operation
 * succeeded. Returns the original `ChannelResult` unchanged.
 */
public inline fun <T> ChannelResult<T>.onSuccess(action: (value: T) -> Unit): ChannelResult<T> {
    if (isSuccess) action(getOrThrow())
    return this
}

/**
 * Performs the given [action] if the operation failed. The result of
 * [ChannelResult.exceptionOrNull] is passed to the [action] parameter.
 * Returns the original `ChannelResult` unchanged.
 */
public inline fun <T> ChannelResult<T>.onFailure(action: (exception: Throwable?) -> Unit): ChannelResult<T> {
    if (isFailure) action(exceptionOrNull())
    return this
}

/**
 * Performs the given [action] if the operation failed because the channel was
 * closed for that operation. The result of [ChannelResult.exceptionOrNull] is
 * passed to the [action] parameter. Returns the original `ChannelResult`
 * unchanged.
 */
public inline fun <T> ChannelResult<T>.onClosed(action: (exception: Throwable?) -> Unit): ChannelResult<T> {
    if (isClosed) action(exceptionOrNull())
    return this
}

/**
 * Internal predicate used by channel machinery: `true` when this result wraps
 * an actual value (a success with a non-null payload).
 */
internal val ChannelResult<*>.holdsValue: Boolean
    get() = isSuccess && token != 0
