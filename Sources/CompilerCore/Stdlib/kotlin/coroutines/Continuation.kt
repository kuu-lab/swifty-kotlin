/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/Continuation.kt.
 */

package kotlin.coroutines

import kotlin.internal.KsSymbolName

// KSP-1131/1139: the continuation contract is declared in Kotlin source;
// the runtime bridges serve compiler-created continuation handles.
public interface Continuation<in T> {
    @KsSymbolName("__kk_coroutine_continuation_context")
    public val context: CoroutineContext

    @KsSymbolName("__kk_coroutine_continuation_resume_with")
    public abstract fun resumeWith(result: Result<T>)
}

public inline fun <T> Continuation<T>.resume(value: T) {
    this.resumeWith(Result.success(value))
}

public inline fun <T> Continuation<T>.resumeWithException(exception: Throwable) {
    this.resumeWith(Result.failure<T>(exception))
}
