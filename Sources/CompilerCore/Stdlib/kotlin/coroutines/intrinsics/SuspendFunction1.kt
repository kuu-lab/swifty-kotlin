/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Receiver-bearing coroutine intrinsics backed by KSwiftK's continuation ABI.
 */

package kotlin.coroutines.intrinsics

import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.internal.InlineOnly

/** Creates an unintercepted coroutine, which begins when the returned continuation is resumed. */
@SinceKotlin("1.3")
public fun <R, T> (suspend R.() -> T).createCoroutineUnintercepted(
    receiver: R,
    completion: Continuation<T>
): Continuation<Unit> {
    val function = this
    return Continuation<Unit>(completion.context) { result ->
        try {
            result.getOrThrow()
            val value = startCoroutineUninterceptedOrReturnFallback(function, receiver, completion)
            if (value !== COROUTINE_SUSPENDED) {
                @Suppress("UNCHECKED_CAST")
                val typed = value as T
                completion.resume(typed)
            }
        } catch (failure: Throwable) {
            completion.resumeWithException(failure)
        }
    }
}

/** Runs the receiver-bearing suspend function until its first suspension. */
@SinceKotlin("1.3")
@InlineOnly
public inline fun <R, T> (suspend R.() -> T).startCoroutineUninterceptedOrReturn(
    receiver: R,
    completion: Continuation<T>
): Any? = startCoroutineUninterceptedOrReturnFallback(this, receiver, completion)
