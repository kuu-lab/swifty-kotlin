/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Lists.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-700: List's covariant nominal shell and directly bridged members are
// source-backed here. The link names stay stable for the built-in list boxes;
// the corresponding Swift registrations remain only as no-stdlib/precompiled
// fallbacks.
public interface List<out E> : Collection<E> {
    @KsSymbolName("__kk_list_get")
    public operator fun get(index: Int): E

    @KsSymbolName("kk_list_is_empty")
    public override fun isEmpty(): Boolean

    @KsSymbolName("kk_list_iterator")
    public fun listIterator(): ListIterator<E>

    @KsSymbolName("kk_list_iterator_at")
    public fun listIterator(index: Int): ListIterator<E>
}
