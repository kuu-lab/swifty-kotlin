/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Set.kt
 * (builtins declaration of kotlin.collections.MutableSet).
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_mutable_set_add")
private external fun <E> __kkMutableSetAdd(set: MutableSet<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_set_remove")
private external fun <E> __kkMutableSetRemove(set: MutableSet<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_set_clear")
private external fun <E> __kkMutableSetClear(set: MutableSet<E>)

@KsSymbolName("__kk_mutable_set_addAll")
private external fun <E> __kkMutableSetAddAll(
    set: MutableSet<E>,
    elements: Collection<out E>
): Boolean

@KsSymbolName("__kk_mutable_set_removeAll")
private external fun <E> __kkMutableSetRemoveAll(
    set: MutableSet<E>,
    elements: Collection<out E>
): Boolean

@KsSymbolName("__kk_mutable_set_retainAll")
private external fun <E> __kkMutableSetRetainAll(
    set: MutableSet<E>,
    elements: Collection<out E>
): Boolean

// KSP-704: the nominal declaration and mutation surface are source-backed.
// The private externals above are the demoted runtime bridges; keeping the
// bridge call in a default interface body avoids repeating the ABI plumbing in
// every concrete MutableSet implementation.
//
// `MutableCollection` will provide `MutableIterable` transitively when its
// separate source migration lands. Keep the direct edge here until then so
// bundled MutableSet values preserve the existing iterable type surface.

/**
 * A generic unordered collection of elements that supports adding and removing
 * elements.
 */
public interface MutableSet<E> : Set<E>, MutableCollection<E>, MutableIterable<E> {
    public fun add(element: E): Boolean = __kkMutableSetAdd(this, element)

    public fun remove(element: E): Boolean = __kkMutableSetRemove(this, element)

    public fun clear() {
        __kkMutableSetClear(this)
    }

    public fun addAll(elements: Collection<out E>): Boolean =
        __kkMutableSetAddAll(this, elements)

    public operator fun plusAssign(element: E) {
        __kkMutableSetAdd(this, element)
    }

    public operator fun plusAssign(elements: Collection<out E>) {
        __kkMutableSetAddAll(this, elements)
    }

    public fun removeAll(elements: Collection<out E>): Boolean =
        __kkMutableSetRemoveAll(this, elements)

    public operator fun minusAssign(element: E) {
        __kkMutableSetRemove(this, element)
    }

    public operator fun minusAssign(elements: Collection<out E>) {
        __kkMutableSetRemoveAll(this, elements)
    }

    public fun retainAll(elements: Collection<out E>): Boolean =
        __kkMutableSetRetainAll(this, elements)
}
