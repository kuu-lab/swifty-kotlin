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
// KSP-1063: `size` redeclares the Collection contract; `@KsSymbolName` cannot
// annotate a property, so its `__kk_collection_size` bridge link is supplied by
// the claimed synthetic registration in HeaderHelpers+SyntheticListResiduals.swift
// (the same mechanism Collection.size uses — the Collection-level bridge, not
// __kk_list_size, so receivers typed as user interfaces extending List keep the
// source-implementation fallback). `iterator` likewise claims the
// `kk_list_iterator` residual registration, keeping the same runtime bridge
// for receivers statically typed as List.
public interface List<out E> : Collection<E> {
    public override val size: Int

    @KsSymbolName("__kk_list_get")
    public operator fun get(index: Int): E

    @KsSymbolName("kk_list_is_empty")
    public override fun isEmpty(): Boolean

    public override fun iterator(): Iterator<E>

    @KsSymbolName("kk_list_iterator")
    public fun listIterator(): ListIterator<E>

    @KsSymbolName("kk_list_iterator_at")
    public fun listIterator(index: Int): ListIterator<E>
}
