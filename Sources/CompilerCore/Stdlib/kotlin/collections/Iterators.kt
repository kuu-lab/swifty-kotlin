/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/Iterators.kt>
 * and <libraries/stdlib/src/kotlin/collections/Iterables.kt>.
 */

package kotlin.collections

/**
 * Returns the given iterator itself. This allows an iterator to be used in a
 * `for` loop without allocating or consuming another iterator.
 */
public inline operator fun <T> Iterator<T>.iterator(): Iterator<T> = this

// KSP-626
// IndexedValue and the indexed Iterable helpers migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//   (kk_list_forEachIndexed, kk_list_withIndex)
//
// `withIndex` materialises eagerly to preserve the existing KSwiftK bridge
// behavior while this surface moves to bundled source.

public data class IndexedValue<out T>(public val index: Int, public val value: T)

public fun <T> Iterable<T>.forEachIndexed(action: (Int, T) -> Unit) {
    var index = 0
    val iterator = iterator()
    while (iterator.hasNext()) {
        action(index, iterator.next())
        index += 1
    }
}

public fun <T> Iterable<T>.withIndex(): List<IndexedValue<T>> {
    val result = mutableListOf<IndexedValue<T>>()
    var index = 0
    val iterator = iterator()
    while (iterator.hasNext()) {
        result.add(IndexedValue(index, iterator.next()))
        index += 1
    }
    return result
}

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
