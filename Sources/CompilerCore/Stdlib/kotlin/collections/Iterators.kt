/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/Iterators.kt>.
 */

package kotlin.collections

// KSP-630
// Iterator terminal HOFs migrated to bundled Kotlin source.

/**
 * Performs the given [operation] on each element of the iterator.
 */
public fun <T> Iterator<T>.forEach(operation: (T) -> Unit): Unit {
    while (hasNext()) {
        operation(next())
    }
}

/**
 * Wraps this iterator into an [Iterator] of [IndexedValue], so every consumed
 * element is accompanied by its index starting at 0.
 */
public fun <T> Iterator<T>.withIndex(): Iterator<IndexedValue<T>> {
    val source = this
    return object : Iterator<IndexedValue<T>> {
        var index = 0

        override fun hasNext(): Boolean = source.hasNext()

        override fun next(): IndexedValue<T> {
            val currentIndex = index
            index += 1
            return IndexedValue(currentIndex, source.next())
        }
    }
}
