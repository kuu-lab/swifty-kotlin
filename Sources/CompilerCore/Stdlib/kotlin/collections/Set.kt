/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Collections.kt
 * (builtins declaration of kotlin.collections.Set).
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-704: the nominal `Set<out E>` declaration is source-backed here, split
// out of SetHOF.kt (which now holds only the extension HOF surface). Unlike
// kotlin-stdlib's `Set`, which inherits every member from `Collection`, this
// interface redeclares `contains`/`isEmpty`/`size`/`iterator` with set-specific
// runtime links (`__kk_set_*`): the runtime Set box does not register in the
// itable, so a `Set<E>`-typed receiver needs a direct bridge rather than
// virtual dispatch through the inherited `Collection` members (BUG-166, see
// `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`).
//
// `size` cannot carry `@KsSymbolName` directly here: the annotation pipeline
// (`HeaderHelpers.swift`'s `registerAnnotations`) only attaches link names to
// `.function`/`.constructor` symbols, not `.property`. The `__kk_set_size`
// bridge for this member therefore stays registered by `registerSetSizeMember`
// in `HeaderHelpers+SyntheticSetStubs.swift`, which remains (along with the
// type shell and `AbstractSet` fallback) for `--no-stdlib` contexts.

/**
 * A generic unordered collection of elements that does not support duplicate elements.
 */
public interface Set<out E> : Collection<E> {
    public override val size: Int

    // These stay body-less abstract overrides (this compiler always flags a
    // body-less interface member abstract — see MutableSet.kt's header
    // comment); every concrete implementer must and already does provide its
    // own override (LinkedHashSet directly; AbstractSet/AbstractCollection
    // subclasses via the inherited AbstractCollection logic). The annotation
    // still lets a receiver statically typed as exactly `Set<E>` (a raw
    // runtime set box with no concrete override in play) dispatch straight to
    // the bridge instead of the itable (BUG-166).
    @KsSymbolName("__kk_set_is_empty")
    public override fun isEmpty(): Boolean

    @KsSymbolName("__kk_set_contains")
    public override operator fun contains(element: @UnsafeVariance E): Boolean

    @KsSymbolName("kk_list_iterator")
    public override fun iterator(): Iterator<E>
}
