/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/Continuation.kt.
 */

package kotlin.coroutines

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.intercepted
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.internal.InlineOnly
import kotlin.internal.KsSymbolName
import kotlin.internal.KsNoInline

// KSP-1131/1139: the continuation contract is declared in Kotlin source;
// the runtime bridges serve compiler-created continuation handles.
public interface Continuation<in T> {
    @KsSymbolName("__kk_coroutine_continuation_context")
    public val context: CoroutineContext

    @KsSymbolName("__kk_coroutine_continuation_resume_with")
    public fun resumeWith(result: Result<T>)
}

public inline fun <T> Continuation<T>.resume(value: T) {
    this.resumeWith(Result.success(value))
}

public inline fun <T> Continuation<T>.resumeWithException(exception: Throwable) {
    this.resumeWith(Result.failure<T>(exception))
}

// Preserve the non-inline API: suspend receivers cross the boxed callable ABI.
@SinceKotlin("1.3")
@KsNoInline
public fun <T> (suspend () -> T).startCoroutine(completion: Continuation<T>) {
    this.createCoroutineUnintercepted(completion).intercepted().resume(Unit)
}

@SinceKotlin("1.3")
@KsNoInline
public fun <R, T> (suspend R.() -> T).startCoroutine(receiver: R, completion: Continuation<T>) {
    this.createCoroutineUnintercepted(receiver, completion).intercepted().resume(Unit)
}

@SinceKotlin("1.3")
@KsNoInline
public fun <T> (suspend () -> T).createCoroutine(completion: Continuation<T>): Continuation<Unit> =
    SafeContinuation<Unit>(this.createCoroutineUnintercepted(completion).intercepted(), COROUTINE_SUSPENDED)

@SinceKotlin("1.3")
@KsNoInline
public fun <R, T> (suspend R.() -> T).createCoroutine(receiver: R, completion: Continuation<T>): Continuation<Unit> =
    SafeContinuation<Unit>(this.createCoroutineUnintercepted(receiver, completion).intercepted(), COROUTINE_SUSPENDED)

@SinceKotlin("1.3")
@InlineOnly
@OptIn(ExperimentalContracts::class)
public suspend inline fun <T> suspendCoroutine(crossinline block: (Continuation<T>) -> Unit): T {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    return suspendCoroutineUninterceptedOrReturn { continuation: Continuation<T> ->
        val safe = SafeContinuation<T>(continuation.intercepted())
        block(safe)
        safe.getOrThrow()
    }
}
