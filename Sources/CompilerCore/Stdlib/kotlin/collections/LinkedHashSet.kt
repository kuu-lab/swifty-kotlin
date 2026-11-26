/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/LinkedHashSet.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_linked_hash_set_init")
private external fun <E> __kkLinkedHashSetInit(set: LinkedHashSet<E>)

@KsSymbolName("kk_list_iterator")
private external fun <E> __kkLinkedHashSetIterator(set: LinkedHashSet<E>): MutableIterator<E>

@KsSymbolName("__kk_collection_size")
private external fun <E> __kkLinkedHashSetSize(set: LinkedHashSet<E>): Int

@KsSymbolName("__kk_collection_containsAll")
private external fun <E> __kkLinkedHashSetContainsAll(
    set: LinkedHashSet<E>,
    elements: Collection<@UnsafeVariance E>
): Boolean

@KsSymbolName("__kk_set_contains")
private external fun <E> __kkLinkedHashSetContains(
    set: LinkedHashSet<E>,
    element: E
): Boolean

@KsSymbolName("__kk_set_is_empty")
private external fun <E> __kkLinkedHashSetIsEmpty(set: LinkedHashSet<E>): Boolean

public open class LinkedHashSet<E> : HashSet<E>, MutableSet<E> {
    init {
        __kkLinkedHashSetInit(this)
    }

    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)

    override val size: Int
        get() = __kkLinkedHashSetSize(this)

    override fun contains(element: E): Boolean = __kkLinkedHashSetContains(this, element)

    override fun isEmpty(): Boolean = __kkLinkedHashSetIsEmpty(this)

    override fun iterator(): MutableIterator<E> = __kkLinkedHashSetIterator(this)

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean =
        __kkLinkedHashSetContainsAll(this, elements)
}
