/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/Runtime.kt>.
 */

package kotlin.native

import kotlin.internal.KsSymbolName

@Deprecated("Initializing runtime is not possible in the new memory model.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public fun initRuntimeIfNeeded() {}

/**
 * Exception thrown when a top-level variable is accessed from an incorrect execution context.
 */
@Deprecated("Support for the legacy memory manager has been completely removed. Usages of this exception can be safely dropped.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class IncorrectDereferenceException : RuntimeException {
    public constructor() : super()

    public constructor(message: String) : super(message)
}

@kotlin.experimental.ExperimentalNativeApi
public typealias ReportUnhandledExceptionHook = (Throwable) -> Unit

@kotlin.experimental.ExperimentalNativeApi
@IgnorableReturnValue
@KsSymbolName("kk_native_setUnhandledExceptionHook")
public external fun setUnhandledExceptionHook(
    hook: ReportUnhandledExceptionHook?
): ReportUnhandledExceptionHook?

@kotlin.experimental.ExperimentalNativeApi
@SinceKotlin("1.6")
@KsSymbolName("kk_native_getUnhandledExceptionHook")
public external fun getUnhandledExceptionHook(): ReportUnhandledExceptionHook?

@kotlin.experimental.ExperimentalNativeApi
@SinceKotlin("1.6")
@KsSymbolName("kk_native_processUnhandledException")
public external fun processUnhandledException(throwable: Throwable): Unit

@kotlin.experimental.ExperimentalNativeApi
@SinceKotlin("1.6")
@KsSymbolName("kk_native_terminateWithUnhandledException")
public external fun terminateWithUnhandledException(throwable: Throwable): Nothing
