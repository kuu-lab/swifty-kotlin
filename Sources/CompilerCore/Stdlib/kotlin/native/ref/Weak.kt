@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.native.ref

import kotlin.experimental.ExperimentalNativeApi
import kotlin.internal.KsSymbolName

@ExperimentalNativeApi
public class WeakReference<T : Any> @KsSymbolName("kk_weak_ref_create") constructor(referred: T) {
    @ExperimentalNativeApi
    public val value: T?
        get() = __weakReferenceGet(this)
}

// Declared with the receiver's own type parameter (not `Any?` + an unchecked
// cast) to match the Future<T>.consumeValue(): T bridge pattern elsewhere.
// The null representation for this Any-erased slot is owned by the runtime
// side (kk_weak_ref_get returns runtimeNullSentinelInt, not bare 0 — see
// KSP-1255's RuntimeNativeAPI.swift fix); this signature change alone does not
// affect that.
@KsSymbolName("kk_weak_ref_get")
private external fun <T : Any> __weakReferenceGet(reference: WeakReference<T>): T?

@KsSymbolName("kk_weak_ref_clear")
private external fun __weakReferenceClear(reference: WeakReference<*>): Int

@PublishedApi
internal var WeakReference<*>.pointer: WeakReferenceImpl?
    get() = null
    set(newValue) {}

@ExperimentalNativeApi
public fun <T : Any> WeakReference<T>.clear() {
    __weakReferenceClear(this)
}

@ExperimentalNativeApi
public fun <T : Any> WeakReference<T>.get(): T? =
    __weakReferenceGet(this)

// Keep the original extension symbol so existing `import kotlin.native.ref.value`
// declarations remain source-compatible. The class member above wins property
// resolution for parameterized references and preserves their T? return type.
@ExperimentalNativeApi
public val WeakReference<*>.value: Any?
    get() = this.get()
