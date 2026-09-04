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

    override fun contains(element: @UnsafeVariance E): Boolean {
        val iterator = iterator()
        while (iterator.hasNext()) {
            if (iterator.next() == element) return true
        }
        return false
    }

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean {
        val iterator = elements.iterator()
        while (iterator.hasNext()) {
            if (!contains(iterator.next())) return false
        }
        return true
    }

    override fun isEmpty(): Boolean = size == 0

    override fun toString(): String = joinToString(", ", "[", "]") { element ->
        if (element === this) "(this Collection)" else element.toString()
    }

    /**
     * Returns a new array containing all elements of this collection.
     */
    protected open fun toArray(): Array<Any?> {
        val result = arrayOfNulls<Any?>(size)
        var index = 0
        for (element in this) {
            result[index++] = element
        }
        return result
    }

    /**
     * Fills the provided array or creates a new array with the collection's elements.
     */
    @Suppress("UNCHECKED_CAST")
    protected open fun <T> toArray(array: Array<T>): Array<T> {
        val destination = if (array.size < size) {
            arrayOfNulls<T>(size) as Array<T>
        } else {
            array
        }
        var index = 0
        for (element in this) {
            destination[index++] = element as T
        }
        return destination
    }
}
