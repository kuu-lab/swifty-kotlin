/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/coroutines/SafeContinuationNative.kt.
 */

package kotlin.coroutines

import kotlin.concurrent.AtomicReference
import kotlin.concurrent.compareAndSet
import kotlin.coroutines.intrinsics.CoroutineSingletons
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED

@PublishedApi
@SinceKotlin("1.3")
internal class SafeContinuation<in T> internal constructor(
    delegate: Continuation<T>,
    initialResult: Any?
) : Continuation<T> {
    private val delegate: Continuation<T> = delegate
    @PublishedApi
    internal constructor(delegate: Continuation<T>) : this(delegate, CoroutineSingletons.UNDECIDED)

    public override val context: CoroutineContext
        get() = this.delegate.context

    // KSwiftK stores Result as a runtime box. Keep the box intact so successful
    // null values and failures remain distinguishable from the state markers.
    private val resultRef = AtomicReference<Any?>(
        if (initialResult === CoroutineSingletons.UNDECIDED ||
            initialResult === CoroutineSingletons.RESUMED ||
            initialResult === COROUTINE_SUSPENDED
        ) initialResult else Result.success(initialResult)
    )

    public override fun resumeWith(result: Result<T>) {
        while (true) {
            val current = this.resultRef.load()
            if (current === CoroutineSingletons.UNDECIDED) {
                if (this.resultRef.compareAndSet(current, result)) return
            } else if (current === COROUTINE_SUSPENDED) {
                if (this.resultRef.compareAndSet(current, CoroutineSingletons.RESUMED)) {
                    this.delegate.resumeWith(result)
                    return
                }
            } else {
                throw IllegalStateException("Already resumed")
            }
        }
    }

    @PublishedApi
    @Suppress("UNCHECKED_CAST")
    internal fun getOrThrow(): Any? {
        var current = this.resultRef.load()
        if (current === CoroutineSingletons.UNDECIDED) {
            if (this.resultRef.compareAndSet(current, COROUTINE_SUSPENDED)) return COROUTINE_SUSPENDED
            current = this.resultRef.load()
        }
        if (current === CoroutineSingletons.RESUMED || current === COROUTINE_SUSPENDED) {
            return COROUTINE_SUSPENDED
        }
        return (current as Result<T>).getOrThrow()
    }
}
