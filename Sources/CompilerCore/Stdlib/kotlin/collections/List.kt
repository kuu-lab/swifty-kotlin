/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Lists.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-700: `get` is source-backed. List runtime boxes do not self-register in
// the itable, so the operator stays an external bridge declaration (same
// pattern as Comparable.compareTo in ../Comparable.kt) rather than a plain
// abstract member.
//
// `listIterator()`/`listIterator(index)` stay compiler residuals in
// Sema/DataFlow/HeaderHelpers+SyntheticListResiduals.swift: they form a
// covariant override pair with MutableList.listIterator() (returns
// MutableListIterator<E>), and MutableList itself is still synthetic
// (KSP-1503/KSP-705). Moving only the List half to source now would hit the
// same precompiled-metadata re-typing gap as MutableIterable.iterator()
// (BUG-200) until MutableList's own migration lands.
//
// `isEmpty()` also stays a compiler residual: its runtime bridge
// (`kk_list_is_empty`) is referenced directly as a name-string constant by
// two KIR lowering tables (CallLowerer+UnresolvedMemberCalls.swift,
// CollectionLiteralLoweringPass+LookupTables+List.swift), independent of the
// Sema member symbol, so it cannot be safely folded into Collection.isEmpty
// inheritance without a dedicated audit of those call sites.
public interface List<out E> : Collection<E> {
    @KsSymbolName("__kk_list_get")
    public external operator fun get(index: Int): E
}
