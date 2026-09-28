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

@KsSymbolName("kk_cpointer_address")
private external fun __nativePointerAddress(pointer: COpaquePointer?): NativePtr

@KsSymbolName("__kk_native_concurrent_detach_object_graph")
private external fun __detachObjectGraph(mode: Int, value: Any?): NativePtr

@ObsoleteWorkersApi
public enum class TransferMode(public val value: Int) {
    SAFE(0),
    UNSAFE(1)
}

/**
 * A detached object graph keeps an opaque stable pointer until it is attached.
 *
 * The public constructors create or restore detached object graphs.
 */
@ObsoleteWorkersApi
@Deprecated("Support for the legacy memory manager has been completely removed. Use the pointed value directly. To pass the value through the C interop, use the StableRef class.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class DetachedObjectGraph<T> internal constructor(pointer: NativePtr) {
    @PublishedApi
    internal val stable: kotlin.concurrent.AtomicNativePtr =
        kotlin.concurrent.AtomicNativePtr(pointer)

    /** Creates a detached graph from the value returned by [producer]. */
    public constructor(mode: TransferMode = TransferMode.SAFE, producer: () -> T) :
        this(__detachObjectGraph(mode.value, producer()))

    /** Restores a detached graph from an opaque C pointer. */
    public constructor(pointer: COpaquePointer?) :
        this(__nativePointerAddress(pointer))

    /** Returns the opaque pointer represented by this detached graph. */
    @ExperimentalForeignApi
    @Suppress("DEPRECATION")
    public fun asCPointer(): COpaquePointer? = __interpretCPointer(stable.value)
}

/**
 * Attaches previously detached object subgraph created by [DetachedObjectGraph].
 * Please note, that once object graph is attached, the [DetachedObjectGraph.stable] pointer does not
 * make sense anymore, and shall be discarded, so attach of one DetachedObjectGraph object can only
 * happen once.
 */
// KSwiftK keeps the managed reference itself as the opaque stable token (see
// __kk_native_concurrent_detach_object_graph / __kk_native_concurrent_attach_object_graph),
// so attaching is a single read of `stable.value` routed through the package
// bridge. The upstream CAS-to-NULL loop is not expressible while the legacy
// kotlin.concurrent.AtomicNativePtr receiver surface remains with KSP-1096.
@ObsoleteWorkersApi
@Deprecated("Support for the legacy memory manager has been completely removed.")
@DeprecatedSinceKotlin(errorSince = "2.1")
@Suppress("DEPRECATION_ERROR")
public inline fun <reified T> DetachedObjectGraph<T>.attach(): T =
    attachObjectGraphInternal(stable.value) as T
