/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/coroutines/debug/StackTraceRecoverable.kt>.
 */

package kotlin.coroutines.debug

import kotlin.coroutines.ExperimentalStdlibCoroutineSupportApi

@SinceKotlin("2.4")
@ExperimentalStdlibCoroutineSupportApi
public interface StackTraceRecoverable<T> where T : Throwable, T : StackTraceRecoverable<T> {
    public fun copyForStackTraceRecovery(): T?
}
