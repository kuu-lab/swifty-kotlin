/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableCollections.kt
 * (builtins declaration of kotlin.collections.MutableIterable).
 */

package kotlin.collections

// KSP-633: The compiler-side `MutableIterable` shell in
// `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` remains the fallback
// for contexts without the bundled stdlib.

public interface MutableIterable<out T> : Iterable<T> {
    public override operator fun iterator(): MutableIterator<T>
}

@IgnorableReturnValue
public fun <T> MutableIterable<T>.removeAll(predicate: (T) -> Boolean): Boolean = filterInPlace(predicate, true)

@IgnorableReturnValue
public fun <T> MutableIterable<T>.retainAll(predicate: (T) -> Boolean): Boolean = filterInPlace(predicate, false)

private fun <T> MutableIterable<T>.filterInPlace(
    predicate: (T) -> Boolean,
    predicateResultToRemove: Boolean
): Boolean {
    var result = false
    val iterator: MutableIterator<T> = iterator()
    while (iterator.hasNext()) {
        if (predicate(iterator.next()) == predicateResultToRemove) {
            iterator.remove()
            result = true
        }
    }
    return result
}
