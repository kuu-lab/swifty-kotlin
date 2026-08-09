/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/TypeAliases.kt,
 * where these names are typealiases onto the java.util collection classes.
 */

package kotlin.collections

// The runtime represents every mutable collection with a single boxed
// implementation per kind, so the aliases target the mutable interfaces directly
// instead of the java.util classes the JVM stdlib points at.

public typealias ArrayList<E> = MutableList<E>

public typealias HashSet<E> = MutableSet<E>

public typealias HashMap<K, V> = MutableMap<K, V>

public typealias LinkedHashMap<K, V> = MutableMap<K, V>

/**
 * Insertion-ordered mutable set.
 *
 * Construction is lowered to the runtime set entry points (`__kk_emptySet` for
 * the empty/capacity forms, `__kk_iterable_toMutableSet` for the copy form) by
 * `CollectionLiteralLoweringPass`, so the constructors carry no Kotlin body.
 */
public open class LinkedHashSet<E> : MutableSet<E> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)
}
