/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/HashSet.kt.
 */

package kotlin.collections

// KSP-704: split out of CollectionAliases.kt into its own 本家-named file
// (docs/stdlib-pipeline.md §6).

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
}
