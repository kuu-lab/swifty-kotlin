/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/coroutines/intrinsics/IntrinsicsNative.kt>
 * and kotlin-stdlib <libraries/stdlib/src/kotlin/coroutines/intrinsics/Intrinsics.kt>.
 */

package kotlin.coroutines.intrinsics

import kotlin.contracts.InvocationKind
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.internal.InlineOnly
import kotlin.internal.KsSymbolName

@KsSymbolName("kk_coroutine_suspended")
private external fun coroutineSuspended(): Any

@KsSymbolName("__kk_continuation_intercepted")
private external fun <T> interceptContinuation(
    continuation: Continuation<T>,
    interceptorKey: CoroutineContext.Key<ContinuationInterceptor>
): Continuation<T>

/**
 * Returns the intercepted runtime continuation, or this continuation unchanged
 * when it is not backed by the runtime interception mechanism.
 *
 * KSwiftK uses Swift-owned continuation handles instead of ContinuationImpl;
 * the bridge owns the representation check and dispatcher adaptation.
 */
@SinceKotlin("1.3")
public fun <T> Continuation<T>.intercepted(): Continuation<T> =
    interceptContinuation(this, ContinuationInterceptor.Key)

/**
 * Marker returned by a coroutine that suspended before producing its result.
 * The runtime owns the singleton so the state-machine lowering can compare it
 * by identity with the value returned from the intrinsic block.
 */
@SinceKotlin("1.3")
public val COROUTINE_SUSPENDED: Any
    get() = coroutineSuspended()

/**
 * Internal state markers used by the native coroutine implementation.
 *
 * The runtime currently represents COROUTINE_SUSPENDED with its existing ABI
 * singleton; the enum remains source-backed for the Kotlin API surface.
 */
@SinceKotlin("1.3")
@PublishedApi
internal enum class CoroutineSingletons {
    COROUTINE_SUSPENDED,
    UNDECIDED,
    RESUMED
}

/**
 * Intrinsic entry point used by coroutine lowering to execute [block] with
 * the current continuation and return either its value or the suspension marker.
 */
@SinceKotlin("1.3")
@InlineOnly
@OptIn(ExperimentalContracts::class)
public suspend inline fun <T> suspendCoroutineUninterceptedOrReturn(crossinline block: (Continuation<T>) -> Any?): T {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    throw NotImplementedError("Implementation of suspendCoroutineUninterceptedOrReturn is intrinsic")
}

/**
 * Fallback used when a suspend function value is not already a compiler-generated
 * continuation implementation.
 */
@Suppress("UNCHECKED_CAST")
@PublishedApi
internal fun <T> startCoroutineUninterceptedOrReturnFallback(
    function: suspend () -> T,
    completion: Continuation<T>
): Any? {
    return (function as Function1<Continuation<T>, Any?>).invoke(completion)
}

/**
 * Markers for the receiver-bearing coroutine intrinsics. They are bodiless so
 * inlining leaves the call in place; the coroutine lowering pass rewrites it
 * into the runtime entry-point ABI (a suspend function value cannot be invoked
 * through a `Function2` cast), and the runtime exports same-named stubs only so the standalone copies of the
 * inline callers still link; the stubs are never executed.
 */
@KsSymbolName("kk_start_coroutine_unintercepted_or_return_with_receiver")
@PublishedApi
internal external fun <R, T> startCoroutineUninterceptedOrReturnWithReceiver(
    function: suspend R.() -> T,
    receiver: R,
    completion: Continuation<T>
): Any?

@KsSymbolName("kk_create_coroutine_unintercepted_with_receiver")
@PublishedApi
internal external fun <R, T> createCoroutineUninterceptedWithReceiver(
    function: suspend R.() -> T,
    receiver: R,
    completion: Continuation<T>
): Continuation<Unit>

/**
 * The runtime continuation is already suitable for KSwiftK's coroutine ABI.
 * Keep this source-backed helper as the identity adaptation until a distinct
 * ContinuationImpl representation is required by the runtime.
 */
@PublishedApi
internal fun <T> wrapWithContinuationImpl(completion: Continuation<T>): Continuation<T> = completion
