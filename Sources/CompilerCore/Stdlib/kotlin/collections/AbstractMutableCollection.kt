/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/AbstractMutableCollection.kt.
 */

package kotlin.collections

// KSP-633: the nominal `AbstractMutableCollection<E>` declaration is
// source-backed here; on bundle load it reuses the synthetic shell registered
// by `HeaderHelpers+SyntheticIterableRegistry.swift`, which remains as the
// fallback for contexts without the bundled stdlib.

/**
 * Provides a skeletal implementation of the [MutableCollection] interface.
 */
public abstract class AbstractMutableCollection<E> protected constructor() : AbstractCollection<E>(), MutableCollection<E> {
    abstract override fun add(element: E): Boolean
}
