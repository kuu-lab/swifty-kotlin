/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractCollection.kt.
 */

package kotlin.collections

// KSP-934: the nominal `Collection<out E>` declaration is source-backed here;
// the compiler-side shell in `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`
// remains the fallback for contexts without the bundled stdlib.
public interface Collection<out E> : Iterable<E> {
    public val size: Int

    public fun isEmpty(): Boolean

    public operator fun contains(element: @UnsafeVariance E): Boolean

    override fun iterator(): Iterator<E>

    public fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean
}

// KSP-633: the nominal `AbstractCollection<out E>` declaration is source-backed
// here; the compiler-side shell in `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`
// remains the fallback for contexts without the bundled stdlib.

/**
 * Provides a skeletal implementation of the read-only [Collection] interface.
 */
public abstract class AbstractCollection<out E> protected constructor() : Collection<E> {
    abstract override val size: Int

    abstract override fun iterator(): Iterator<E>
}
