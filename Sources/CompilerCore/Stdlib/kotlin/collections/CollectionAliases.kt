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

public final class ArrayList<E> : MutableList<E>, RandomAccess, AbstractMutableList<E> {
    init {
        __kkArrayListInit(this)
    }

    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)
}

public typealias HashSet<E> = MutableSet<E>

public typealias HashMap<K, V> = MutableMap<K, V>

public typealias LinkedHashMap<K, V> = MutableMap<K, V>

/**
 * Insertion-ordered mutable set.
 *
 * Construction is lowered to the runtime set entry points (`__kk_emptySet` for
 * the empty/capacity forms, `__kk_iterable_toMutableSet` for the copy form) by
 * `CollectionLiteralLoweringPass`. The `init` block additionally attaches a
 * backing `RuntimeSetBox` to source-allocated instances (including user
 * subclasses) so `MutableSet` member calls operate on real storage.
 */
@KsSymbolName("__kk_linked_hash_set_init")
private external fun <E> __kkLinkedHashSetInit(set: LinkedHashSet<E>)

public open class LinkedHashSet<E> : MutableSet<E> {
    init {
        __kkLinkedHashSetInit(this)
    }

    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)
}
