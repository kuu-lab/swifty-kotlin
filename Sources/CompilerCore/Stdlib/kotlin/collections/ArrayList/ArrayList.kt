/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/ArrayList.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// ArrayList has a concrete nominal identity in Kotlin/Native and Kotlin/Wasm.
// CollectionLiteralLoweringPass maps its constructors to the tagged list box
// bridges, while the declaration preserves the public class hierarchy. Every
// instance is a RuntimeListBox, so members bind directly to the shared list
// storage bridges instead of going through the AbstractMutableList defaults
// (which read modCount as an object field — see TODO.md BUG-247). The
// Kotlin/Native backing-array storage is runtime-managed. Mutability checks
// query the list box's read-only state before delegating mutation to its bridges,
// so `ensureCapacity` / `trimToSize` are contract-only no-ops.
@KsSymbolName("__kk_array_list_init")
private external fun <E> __kkArrayListInit(list: ArrayList<E>)

@KsSymbolName("__kk_collection_size")
private external fun <E> __kkArrayListSize(list: ArrayList<E>): Int

@KsSymbolName("__kk_builder_list_freeze")
private external fun <E> __kkArrayListBuild(list: ArrayList<E>): List<E>

@KsSymbolName("__kk_array_list_is_read_only")
private external fun <E> __kkArrayListIsReadOnly(list: ArrayList<E>): Boolean

@KsSymbolName("__kk_mutable_list_set")
private external fun <E> __kkArrayListSet(list: ArrayList<E>, index: Int, element: E): E

@KsSymbolName("__kk_mutable_list_add")
private external fun <E> __kkArrayListAdd(list: ArrayList<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_list_add_at")
private external fun <E> __kkArrayListAddAt(list: ArrayList<E>, index: Int, element: E)

@KsSymbolName("__kk_mutable_list_addAll")
private external fun <E> __kkArrayListAddAll(list: ArrayList<E>, elements: Collection<E>): Boolean

@KsSymbolName("__kk_mutable_list_addAll_at")
private external fun <E> __kkArrayListAddAllAt(list: ArrayList<E>, index: Int, elements: Collection<E>): Boolean

@KsSymbolName("__kk_mutable_list_clear")
private external fun <E> __kkArrayListClear(list: ArrayList<E>)

@KsSymbolName("__kk_mutable_list_removeAt")
private external fun <E> __kkArrayListRemoveAt(list: ArrayList<E>, index: Int): E

@KsSymbolName("__kk_mutable_list_remove")
private external fun <E> __kkArrayListRemove(list: ArrayList<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_list_removeAll")
private external fun <E> __kkArrayListRemoveAll(list: ArrayList<E>, elements: Collection<E>): Boolean

@KsSymbolName("__kk_mutable_list_retainAll")
private external fun <E> __kkArrayListRetainAll(list: ArrayList<E>, elements: Collection<E>): Boolean

public final class ArrayList<E> : MutableList<E>, RandomAccess, AbstractMutableList<E> {
    init {
        __kkArrayListInit(this)
    }

    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)

    @PublishedApi
    internal fun build(): List<E> {
        checkIsMutable()
        return __kkArrayListBuild(this)
    }

    override val size: Int
        get() = __kkArrayListSize(this)

    @KsSymbolName("kk_list_is_empty")
    override external fun isEmpty(): Boolean

    @KsSymbolName("__kk_list_get")
    override external operator fun get(index: Int): E

    @IgnorableReturnValue
    override operator fun set(index: Int, element: E): E {
        checkIsMutable()
        return __kkArrayListSet(this, index, element)
    }

    @KsSymbolName("kk_op_contains")
    override external operator fun contains(element: E): Boolean

    @KsSymbolName("__kk_collection_containsAll")
    override external fun containsAll(elements: Collection<E>): Boolean

    override fun indexOf(element: E): Int {
        var index = 0
        while (index < size) {
            if (get(index) == element) return index
            index += 1
        }
        return -1
    }

    override fun lastIndexOf(element: E): Int {
        var index = size - 1
        while (index >= 0) {
            if (get(index) == element) return index
            index -= 1
        }
        return -1
    }

    @KsSymbolName("kk_list_iterator")
    override external fun iterator(): MutableIterator<E>

    @KsSymbolName("kk_list_iterator")
    override external fun listIterator(): MutableListIterator<E>

    @KsSymbolName("kk_list_iterator_at")
    override external fun listIterator(index: Int): MutableListIterator<E>

    @IgnorableReturnValue
    override fun add(element: E): Boolean {
        checkIsMutable()
        return __kkArrayListAdd(this, element)
    }

    override fun add(index: Int, element: E) {
        checkIsMutable()
        __kkArrayListAddAt(this, index, element)
    }

    @IgnorableReturnValue
    override fun addAll(elements: Collection<E>): Boolean {
        checkIsMutable()
        return __kkArrayListAddAll(this, elements)
    }

    @IgnorableReturnValue
    override fun addAll(index: Int, elements: Collection<E>): Boolean {
        checkIsMutable()
        return __kkArrayListAddAllAt(this, index, elements)
    }

    // AbstractMutableList's default clear() (removeRange -> listIterator) reads
    // the inherited modCount field, which is not addressable on ArrayList's
    // runtime-backed storage (see TODO.md BUG-247).
    override fun clear() {
        checkIsMutable()
        __kkArrayListClear(this)
    }

    @IgnorableReturnValue
    override fun removeAt(index: Int): E {
        checkIsMutable()
        return __kkArrayListRemoveAt(this, index)
    }

    @IgnorableReturnValue
    override fun remove(element: E): Boolean {
        checkIsMutable()
        return __kkArrayListRemove(this, element)
    }

    @IgnorableReturnValue
    override fun removeAll(elements: Collection<E>): Boolean {
        checkIsMutable()
        return __kkArrayListRemoveAll(this, elements)
    }

    @IgnorableReturnValue
    override fun retainAll(elements: Collection<E>): Boolean {
        checkIsMutable()
        return __kkArrayListRetainAll(this, elements)
    }

    @KsSymbolName("kk_list_subList")
    override external fun subList(fromIndex: Int, toIndex: Int): MutableList<E>

    // Capacity is managed by the runtime list box; the contract only promises
    // the list stays usable, so both members are contract-only no-ops.
    public fun trimToSize() {
    }

    public fun ensureCapacity(minCapacity: Int) {
    }

    private fun checkIsMutable() {
        if (__kkArrayListIsReadOnly(this)) throw UnsupportedOperationException()
    }

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is List<*>) return false
        if (other.size != size) return false
        val otherIterator = other.iterator()
        for (element in this) {
            if (element != otherIterator.next()) return false
        }
        return true
    }

    override fun hashCode(): Int {
        var hashCode = 1
        for (element in this) {
            hashCode = 31 * hashCode + (element?.hashCode() ?: 0)
        }
        return hashCode
    }

    @KsSymbolName("kk_list_to_string")
    override external fun toString(): String
}
