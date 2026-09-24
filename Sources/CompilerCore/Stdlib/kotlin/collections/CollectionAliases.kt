/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/TypeAliases.kt,
 * where these names are typealiases onto the java.util collection classes.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// ArrayList has a concrete nominal identity in Kotlin/Native and Kotlin/Wasm.
// CollectionLiteralLoweringPass maps its constructors to the tagged list box
// bridges, while the declaration preserves the public class hierarchy.
@KsSymbolName("__kk_array_list_init")
private external fun <E> __kkArrayListInit(list: ArrayList<E>)

@KsSymbolName("__kk_collection_size")
private external fun <E> __kkArrayListSize(list: ArrayList<E>): Int

public final class ArrayList<E> : MutableList<E>, RandomAccess, AbstractMutableList<E> {
    init {
        __kkArrayListInit(this)
    }

    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)

    override val size: Int
        get() = __kkArrayListSize(this)

    @KsSymbolName("__kk_list_get")
    override external operator fun get(index: Int): E

    @KsSymbolName("kk_op_contains")
    override external operator fun contains(element: @UnsafeVariance E): Boolean

    @KsSymbolName("__kk_collection_containsAll")
    override external fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean

    @KsSymbolName("kk_list_iterator")
    override external fun iterator(): Iterator<E>

    @KsSymbolName("kk_list_subList")
    override external fun subList(fromIndex: Int, toIndex: Int): MutableList<E>

    @KsSymbolName("__kk_mutable_list_add")
    override external fun add(element: E): Boolean

    @KsSymbolName("__kk_mutable_list_add_at")
    override external fun add(index: Int, element: E)

    @KsSymbolName("__kk_mutable_list_removeAt")
    override external fun removeAt(index: Int): E

    @KsSymbolName("__kk_mutable_list_set")
    override external fun set(index: Int, element: E): E

    // AbstractMutableList's default clear() (removeRange -> listIterator) reads
    // the inherited modCount field, which is not addressable on ArrayList's
    // runtime-backed storage (see TODO.md BUG-247). Bind directly to the
    // runtime primitive instead, matching the other members above.
    @KsSymbolName("__kk_mutable_list_clear")
    override external fun clear()
}

// KSP-704: HashSet and LinkedHashSet moved to their own upstream-named files
// (HashSet.kt / LinkedHashSet.kt). KSP-703: LinkedHashMap moved the same way
// (LinkedHashMap.kt).
