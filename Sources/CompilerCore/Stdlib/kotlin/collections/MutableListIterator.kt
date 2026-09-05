/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableListIterator.kt.
 */

package kotlin.collections

// KSP-945/KSP-1073: keep the public MutableListIterator contract in bundled
// Kotlin source. Runtime-backed mutation is registered separately.

/**
 * An iterator over a mutable list that supports element insertion, replacement,
 * and removal while iterating.
 */
public interface MutableListIterator<T> : ListIterator<T>, MutableIterator<T> {
    public override fun next(): T

    public override fun hasNext(): Boolean

    public override fun remove(): Unit

    public fun set(element: T): Unit

    public fun add(element: T): Unit
}
