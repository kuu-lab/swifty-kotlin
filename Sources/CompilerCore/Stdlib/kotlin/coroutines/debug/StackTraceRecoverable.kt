/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/coroutines/debug/StackTraceRecoverable.kt>.
 */

package kotlin.coroutines.debug

import kotlin.coroutines.ExperimentalStdlibCoroutineSupportApi

/** Allows a throwable to supply its own copy for coroutine stack trace recovery. */
@SinceKotlin("2.4")
@ExperimentalStdlibCoroutineSupportApi
public interface StackTraceRecoverable<T> where T : Throwable, T : StackTraceRecoverable<T> {
    /** Returns a copy, preferably with the original throwable as its cause, or null to decline recovery. */
    public fun copyForStackTraceRecovery(): T?
}
