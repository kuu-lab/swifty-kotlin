/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the license/LICENSE.txt file.
 *
 * Derived from kotlin-native/Interop/Runtime/src/main/kotlin/kotlinx/cinterop/StableRef.kt.
 */

package kotlinx.cinterop

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_stable_ref_create")
internal external fun __stableRefCreate(any: Any): COpaquePointer

@KsSymbolName("kk_stable_ref_deref")
internal external fun __stableRefDeref(pointer: COpaquePointer): Any?

@KsSymbolName("kk_stable_ref_dispose")
internal external fun __stableRefDispose(pointer: COpaquePointer): Unit

/**
 * This class provides a way to create a stable handle to any Kotlin object.
 * After converting to CPointer it can be safely passed to native code e.g. to be received
 * in a Kotlin callback.
 *
 * Any StableRef should be manually disposed.
 */
@Suppress("NON_PUBLIC_PRIMARY_CONSTRUCTOR_OF_INLINE_CLASS")
@ExperimentalForeignApi
public value class StableRef<out T : Any> internal constructor(
    private val stablePtr: COpaquePointer
) {

    public companion object {
        /** Creates a handle for given object. */
        public fun <T : Any> create(any: T): StableRef<T> = StableRef(__stableRefCreate(any))
    }

    /** Converts the handle to C pointer. */
    public fun asCPointer(): COpaquePointer = stablePtr

    /** Disposes the handle. It must not be used after that. */
    public fun dispose() {
        __stableRefDispose(stablePtr)
    }

    /** Returns the object this handle was created for. */
    @Suppress("UNCHECKED_CAST")
    public fun get(): T = __stableRefDeref(stablePtr) as T
}

/** Converts to [StableRef] this opaque pointer produced by [StableRef.asCPointer]. */
@ExperimentalForeignApi
public fun <T : Any> COpaquePointer.asStableRef(): StableRef<T> {
    val ref = StableRef<T>(this)
    ref.get()
    return ref
}
