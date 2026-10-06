/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/ContinuationInterceptor.kt.
 */

package kotlin.coroutines

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_is_native_dispatcher")
internal external fun __isNativeDispatcher(element: CoroutineContext.Element): Boolean

public interface ContinuationInterceptor : CoroutineContext.Element {
    // KUU-1395: `ContinuationInterceptor`/`ContinuationInterceptor.Key`
    // evaluates to a runtime key singleton (same pattern as `Job.Key`), so
    // `ctx[ContinuationInterceptor]`/`ctx.minusKey(ContinuationInterceptor)`
    // resolve the context's dispatcher element — a runBlocking event loop.
    @KsSymbolName("kk_continuation_interceptor_key")
    public companion object Key : CoroutineContext.Key<ContinuationInterceptor>

    public fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T>

    public fun releaseInterceptedContinuation(continuation: Continuation<*>) {}

    @OptIn(ExperimentalStdlibApi::class)
    @Suppress("UNCHECKED_CAST")
    public override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
        if (key is AbstractCoroutineContextKey<*, *>) {
            val elementKey = if (__isNativeDispatcher(this)) Key else this.key
            return if (key.isSubKey(elementKey)) key.tryCast(this) as? E else null
        }
        return if (ContinuationInterceptor.Key === key) this as E else null
    }

    @OptIn(ExperimentalStdlibApi::class)
    public override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext {
        if (key is AbstractCoroutineContextKey<*, *>) {
            val elementKey = if (__isNativeDispatcher(this)) Key else this.key
            return if (key.isSubKey(elementKey) && key.tryCast(this) != null) EmptyCoroutineContext else this
        }
        return if (ContinuationInterceptor.Key === key) EmptyCoroutineContext else this
    }
}
