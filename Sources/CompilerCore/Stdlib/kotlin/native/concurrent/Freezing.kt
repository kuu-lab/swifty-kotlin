/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Freezing.kt>.
 */

@file:Suppress("DEPRECATION_ERROR")

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName

/**
 * Exception thrown whenever freezing is not possible.
 *
 * @param toFreeze the object that could not be frozen.
 * @param blocker the first object that prevents freezing.
 */
@Deprecated("Support for the legacy memory manager has been completely removed. Usages of this exception can be safely dropped.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class FreezingException : RuntimeException {
    @KsSymbolName("__kk_freezing_exception_new")
    public constructor(toFreeze: Any, blocker: Any)
}

@Deprecated(
    "Support for the legacy memory manager has been completely removed. Usages of this function can be safely dropped.",
    ReplaceWith("this")
)
@DeprecatedSinceKotlin(errorSince = "2.1")
public fun <T> T.freeze(): T = this
