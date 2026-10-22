/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Set.kt
 * (builtins declaration of kotlin.collections.MutableSet).
 */

package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.js.ExperimentalJsCollectionsApi
import kotlin.js.ExperimentalJsExport
import kotlin.js.collections.JsSet
import kotlin.js.collections.createJsSetViewFrom

// The mutation members stay `external` declarations bound directly to their
// demoted set-specific runtime bridges, matching the MutableCollection
// migration. Bound this way they keep providing an implementation to every
// concrete MutableSet without repeating the ABI plumbing, while staying
// recognizable as runtime bridges — e.g. an unqualified `super.removeAll()`
// call must not treat them as an independent Kotlin default competing with a
// concrete superclass implementation.
//
// `MutableCollection` will provide `MutableIterable` transitively when its
// separate source migration lands. Keep the direct edge here until then so
// bundled MutableSet values preserve the existing iterable type surface.

public interface MutableSet<E> : Set<E>, MutableCollection<E>, MutableIterable<E> {
    @KsSymbolName("__kk_mutable_set_add")
    @IgnorableReturnValue
    public override external fun add(element: E): Boolean

    @KsSymbolName("__kk_mutable_set_remove")
    @IgnorableReturnValue
    public override external fun remove(element: E): Boolean

    @KsSymbolName("__kk_mutable_set_clear")
    public override external fun clear(): Unit

    @KsSymbolName("__kk_mutable_collection_addAll_throwing")
    @IgnorableReturnValue
    public override external fun addAll(elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_set_removeAll")
    @IgnorableReturnValue
    public override external fun removeAll(elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_set_retainAll")
    @IgnorableReturnValue
    public override external fun retainAll(elements: Collection<out E>): Boolean

    @ExperimentalJsExport
    @ExperimentalJsCollectionsApi
    @SinceKotlin("2.0")
    public fun asJsSetView(): JsSet<E> = createJsSetViewFrom(this)
}
