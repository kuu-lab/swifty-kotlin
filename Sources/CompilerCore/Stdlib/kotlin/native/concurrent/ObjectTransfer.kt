/*
 * Copyright 2010-2023 JetBrains s.r.o. Use of this source code is governed by
 * the Apache 2.0 license.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/ObjectTransfer.kt.
 */

@file:OptIn(ExperimentalForeignApi::class)

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName
import kotlin.native.internal.NativePtr
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.ExperimentalForeignApi

// KSwiftK represents C pointers as runtime handles. Reuse the existing
// cinterop handle constructor for the NativePtr-to-CPointer identity cast.
@KsSymbolName("kk_cpointer_new")
private external fun __interpretCPointer(rawValue: NativePtr): COpaquePointer?

@ObsoleteWorkersApi
public enum class TransferMode(public val value: Int) {
    SAFE(0),
    UNSAFE(1)
}

/**
 * A detached object graph keeps an opaque stable pointer until it is attached.
 *
 * The public constructors are owned by KSP-1234. This slice supplies the
 * internal storage and receiver members used by the existing native helpers.
 */
@ObsoleteWorkersApi
@Deprecated("Support for the legacy memory manager has been completely removed. Use the pointed value directly. To pass the value through the C interop, use the StableRef class.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class DetachedObjectGraph<T> internal constructor(pointer: NativePtr) {
    @PublishedApi
    internal val stable: kotlin.concurrent.AtomicNativePtr =
        kotlin.concurrent.AtomicNativePtr(pointer)

    /** Returns the opaque pointer represented by this detached graph. */
    @ExperimentalForeignApi
    @Suppress("DEPRECATION")
    public fun asCPointer(): COpaquePointer? = __interpretCPointer(stable.value)
}
