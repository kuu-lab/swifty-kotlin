/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/HashSet.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-704: split out of CollectionAliases.kt into its own 本家-named file
// (docs/stdlib-pipeline.md §6).
// KSP-1057: the receiver members are source-backed on the nominal class.
// Every instance is a tagged RuntimeSetBox produced by the `HashSet(...)` /
// `hashSetOf` constructor lowering (`CollectionLiteralLoweringPass`), so the
// members bind directly to the shared set storage bridges instead of object
// fields or a class vtable. The Kotlin/Native `KonanSet` marker interface and
// its backing `HashMap` storage are platform internals that KSwiftK does not
// model.

@KsSymbolName("__kk_set_size")
private external fun <E> __kkHashSetSize(set: HashSet<E>): Int

@KsSymbolName("__kk_builder_set_freeze")
private external fun <E> __kkHashSetBuild(set: HashSet<E>): Set<E>

/**
 * Hash-based mutable set implementation.
 *
 * The Kotlin/Native `KonanSet` marker is an internal platform type that is not
 * modeled by KSwiftK. The public nominal hierarchy is preserved here while
 * the shared runtime set box supplies storage and collection operations.
 */
public class HashSet<E> : AbstractMutableSet<E>, MutableSet<E> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)

    override val size: Int
        get() = __kkHashSetSize(this)

    @KsSymbolName("__kk_set_is_empty")
    override external fun isEmpty(): Boolean

    @KsSymbolName("__kk_set_contains")
    override external operator fun contains(element: E): Boolean

    @KsSymbolName("kk_list_iterator")
    override external fun iterator(): MutableIterator<E>

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_set_add")
    override external fun add(element: E): Boolean

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_set_remove")
    override external fun remove(element: E): Boolean

    @KsSymbolName("__kk_mutable_set_clear")
    override external fun clear()

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_set_addAll")
    override external fun addAll(elements: Collection<E>): Boolean

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_set_removeAll")
    override external fun removeAll(elements: Collection<E>): Boolean

    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_set_retainAll")
    override external fun retainAll(elements: Collection<E>): Boolean

    @PublishedApi
    internal fun build(): Set<E> = __kkHashSetBuild(this)

    /**
     * Returns the element stored in this set that is equal to [element]
     * (the `KonanSet.getElement` contract, used for ObjC interop upstream).
     */
    @Deprecated("This function is not supposed to be used directly.")
    @DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
    fun getElement(element: E): E? {
        val iterator = iterator()
        while (iterator.hasNext()) {
            val current = iterator.next()
            if (current == element) return current
        }
        return null
    }
}
