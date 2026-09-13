/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Atomics.kt>.
 */

@file:OptIn(ExperimentalForeignApi::class)

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.NativePtr

/**
 * A [Long] value that is always updated atomically.
 *
 * This is the legacy Kotlin/Native atomic API. Use
 * `kotlin.concurrent.atomics.AtomicLong` instead.
 */
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicLong instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicLong"),
    DeprecationLevel.ERROR
)
public class AtomicLong {
    @KsSymbolName("kk_atomic_long_create")
    public constructor(value: Long = 0L)
}

/**
 * A deprecated atomic wrapper around a native pointer.
 *
 * This declaration owns the top-level constructor only. The value property
 * and member operations remain separate migration surfaces.
 */
@Deprecated("Use kotlin.concurrent.atomics.AtomicNativePtr instead.", ReplaceWith("kotlin.concurrent.atomics.AtomicNativePtr"), DeprecationLevel.ERROR)
public class AtomicNativePtr {
    public constructor(value: NativePtr)
}

// KSP-1226: Keep the legacy native AtomicReference constructor source-backed.
// Its value and atomic member operations are owned by KSP-1227.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class AtomicReference<T>(value: T)

// KSP-1236: Keep the top-level class and constructor source-backed. The
// value property and member operations are owned by KSP-1237.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class FreezableAtomicReference<T> {
    @KsSymbolName("kk_freezable_atomic_ref_create")
    public constructor(value: T)
}
