/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Lazy.kt>.
 */

@file:Suppress("DEPRECATION_ERROR")

package kotlin.native.concurrent

@Deprecated(
    "Support for the legacy memory manager has been completely removed. Use lazy() instead.",
    ReplaceWith("lazy(initializer)")
)
@DeprecatedSinceKotlin(errorSince = "2.1")
public fun <T> atomicLazy(initializer: () -> T): Lazy<T> = lazy(initializer)
