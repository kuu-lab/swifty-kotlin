/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/HashSet.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// Direct instances are tagged RuntimeSetBoxes produced by the `HashSet(...)` /
// `hashSetOf` constructor lowering (`CollectionLiteralLoweringPass`). Members
// bind to the shared set storage bridges, which also support the backing boxes
// attached to source-allocated HashSet subclasses. The Kotlin/Native
// `KonanSet` marker interface and its backing `HashMap` storage are platform
// internals that KSwiftK does not model.

@KsSymbolName("__kk_set_size")
private external fun <E> __kkHashSetSize(set: HashSet<E>): Int

@KsSymbolName("__kk_builder_set_freeze")
private external fun <E> __kkHashSetBuild(set: HashSet<E>): Set<E>

// The shared initializer attaches set storage without replacing the source
// object's nominal identity or its subclass fields.
@KsSymbolName("__kk_linked_hash_set_init")
private external fun <E> __kkHashSetInit(set: HashSet<E>)

/**
 * The Kotlin/Native `KonanSet` marker is an internal platform type that is not
 * modeled by KSwiftK. The public nominal hierarchy is preserved here while
 * the shared runtime set box supplies storage and collection operations.
 */
public open class HashSet<E> : AbstractMutableSet<E>, MutableSet<E> {
    init {
        __kkHashSetInit(this)
    }

    constructor()
    constructor(initialCapacity: Int) : this(initialCapacity, 0.75f)
    constructor(initialCapacity: Int, loadFactor: Float) {
        require(initialCapacity >= 0) { "Illegal Capacity: $initialCapacity" }
        require(loadFactor > 0f) { "Illegal Load: $loadFactor" }
    }
    constructor(elements: Collection<E>) : this() {
        addAll(elements)
    }

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
