/*
 * KSP-1256: Kotlin/Native WeakReference receiver API.
 *
 * The runtime owns the weak-reference handle and its referent state. Keep the
 * public API in Kotlin source while using private bridges for those operations.
 */

@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.native.ref

import kotlin.experimental.ExperimentalNativeApi
import kotlin.internal.KsSymbolName

// KSP-1255: the public constructor is source-backed here; the runtime
// allocates and owns the weak-reference handle, so construction bridges
// straight to the factory instead of allocating a plain object first.
@ExperimentalNativeApi
public class WeakReference<T : Any> @KsSymbolName("kk_weak_ref_create") constructor(referred: T)

// Declared with the receiver's own type parameter (not `Any?` + an unchecked
// cast) to match the Future<T>.consumeValue(): T bridge pattern elsewhere in
// this file's package. The null representation for this Any-erased slot is
// owned by the runtime side (kk_weak_ref_get returns runtimeNullSentinelInt,
// not bare 0 — see KSP-1255's RuntimeNativeAPI.swift fix); this signature
// change alone does not affect that.
@KsSymbolName("kk_weak_ref_get")
private external fun <T : Any> __weakReferenceGet(reference: WeakReference<T>): T?

@KsSymbolName("kk_weak_ref_clear")
private external fun __weakReferenceClear(reference: WeakReference<*>): Int

/** Backing store compatibility for the Kotlin/Native WeakReference contract. */
@PublishedApi
internal var WeakReference<*>.pointer: WeakReferenceImpl?
    get() = null
    set(newValue) {}

/** Clears the weak reference to its referent. */
@ExperimentalNativeApi
public fun <T : Any> WeakReference<T>.clear() {
    __weakReferenceClear(this)
}

/** Returns the referent while it is still alive, or null after collection. */
@ExperimentalNativeApi
public fun <T : Any> WeakReference<T>.get(): T? =
    __weakReferenceGet(this)

// Generic extension property type parameters are not supported by this parser;
// the star-projected receiver preserves the nullable read contract.
/** Returns the referent while it is still alive, or null after collection. */
@ExperimentalNativeApi
public val WeakReference<*>.value: Any?
    get() = this.get()
