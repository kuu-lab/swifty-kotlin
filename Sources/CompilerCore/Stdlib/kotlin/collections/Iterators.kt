/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/Iterators.kt>
 * and <libraries/stdlib/src/kotlin/collections/Iterables.kt>.
 */

package kotlin.collections

// KSP-626
// IndexedValue and the indexed Iterable helpers migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift
//   (kk_list_forEachIndexed, kk_list_withIndex)
//
// `withIndex` materialises eagerly instead of returning the upstream lazy
// `IndexingIterable`: for-in over a value whose static type is an interface
// (`Iterable<T>`) does not bind the real `iterator()` yet (BUG-167).

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
