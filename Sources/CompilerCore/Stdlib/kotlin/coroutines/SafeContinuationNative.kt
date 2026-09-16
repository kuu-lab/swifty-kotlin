/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/coroutines/SafeContinuationNative.kt>.
 */

package kotlin.coroutines

// KSP-1147: expose the published internal SafeContinuation constructor from
// bundled Kotlin source. Its continuation behavior remains in the receiver
// members handled by the follow-up SafeContinuation migration.
@PublishedApi
@SinceKotlin("1.3")
internal class SafeContinuation<in T> : Continuation<T> {
    @PublishedApi
    internal constructor(delegate: Continuation<T>)
}
