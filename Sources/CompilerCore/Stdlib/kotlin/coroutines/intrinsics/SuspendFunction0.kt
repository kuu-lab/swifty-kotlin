/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/coroutines/intrinsics/IntrinsicsNative.kt.
 */

package kotlin.coroutines.intrinsics

import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.internal.InlineOnly

/** Creates a fresh continuation without applying the completion's interceptor. */
@SinceKotlin("1.3")
public fun <T> (suspend () -> T).createCoroutineUnintercepted(
    completion: Continuation<T>
): Continuation<Unit> {
    val function = this
    return Continuation<Unit>(completion.context) { result ->
        try {
            result.getOrThrow()
            val value = startCoroutineUninterceptedOrReturnFallback(function, completion)
            if (value !== COROUTINE_SUSPENDED) {
                @Suppress("UNCHECKED_CAST")
                completion.resume(value as T)
            }
        } catch (failure: Throwable) {
            completion.resumeWithException(failure)
        }
    }
}

/** Runs until the first suspension, returning the result or suspended marker. */
@SinceKotlin("1.3")
@InlineOnly
public inline fun <T> (suspend () -> T).startCoroutineUninterceptedOrReturn(
    completion: Continuation<T>
): Any? = startCoroutineUninterceptedOrReturnFallback(this, completion)
