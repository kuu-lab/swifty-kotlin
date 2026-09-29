/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/coroutines/intrinsics/IntrinsicsNative.kt.
 */

package kotlin.coroutines.intrinsics

import kotlin.coroutines.Continuation
import kotlin.internal.InlineOnly
import kotlin.internal.KsSymbolName

// A suspend function value cannot be invoked through a `Function1` cast at
// runtime, so these bodiless markers keep the intrinsic's call name in KIR.
// The coroutine lowering pass rewrites calls with these names into the runtime
// entry-point ABI. They must stay bodiless so inlining does not expand them.
@KsSymbolName("createCoroutineUnintercepted")
@PublishedApi
internal external fun <T> createCoroutineUninterceptedNoReceiver(
    function: suspend () -> T,
    completion: Continuation<T>
): Continuation<Unit>

@KsSymbolName("startCoroutineUninterceptedOrReturn")
@PublishedApi
internal external fun <T> startCoroutineUninterceptedOrReturnNoReceiver(
    function: suspend () -> T,
    completion: Continuation<T>
): Any?

/** Creates a fresh continuation without applying the completion's interceptor. */
@SinceKotlin("1.3")
@InlineOnly
public inline fun <T> (suspend () -> T).createCoroutineUnintercepted(
    completion: Continuation<T>
): Continuation<Unit> = createCoroutineUninterceptedNoReceiver(this, completion)

/** Runs until the first suspension, returning the result or suspended marker. */
@SinceKotlin("1.3")
@InlineOnly
public inline fun <T> (suspend () -> T).startCoroutineUninterceptedOrReturn(
    completion: Continuation<T>
): Any? = startCoroutineUninterceptedOrReturnNoReceiver(this, completion)
