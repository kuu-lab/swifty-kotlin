/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Arrays.kt.
 */

package kotlin.collections

/**
 * Returns a single list of all elements from all arrays in the given array.
 */
public fun <T> Array<out Array<out T>>.flatten(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        result.addAll(element)
    }
    return result
}

// KUU-541: upstream kotlin-stdlib has no Array<out Iterable<T>>.flatten();
// this overload is a deliberate superset so Array receivers with Iterable
// elements (e.g. arrayOf(listOf(1, 2), listOf(3))) resolve the same way.
public fun <T> Array<out Iterable<T>>.flatten(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        result.addAll(element)
    }
    return result
}
