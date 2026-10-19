/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/Iterators.kt>
 * and <libraries/stdlib/src/kotlin/collections/Iterables.kt>.
 */

package kotlin.collections

/**
 * Allows an iterator to be used in a `for` loop without allocating or
 * consuming another iterator.
 */
public inline operator fun <T> Iterator<T>.iterator(): Iterator<T> = this

public data class IndexedValue<out T>(public val index: Int, public val value: T)

// KSP-977 / KUU-604
// Iterable.forEach and forEachIndexed stay inline so a direct return in their
// lambdas can escape the enclosing caller. Compatibility-only runtime bridges
// remain available for receiver-specific dispatch paths.
public inline fun <T> Iterable<T>.forEach(action: (T) -> Unit): Unit {
    val iterator = iterator()
    while (iterator.hasNext()) {
        action(iterator.next())
    }
}

public inline fun <T> Iterable<T>.forEachIndexed(action: (Int, T) -> Unit) {
    var index = 0
    val iterator = iterator()
    while (iterator.hasNext()) {
        action(index, iterator.next())
        index += 1
    }
}

internal class IndexingIterator<out T>(
    private val source: Iterator<T>
) : Iterator<IndexedValue<T>> {
    private var index = 0

    override fun hasNext(): Boolean = source.hasNext()

    override fun next(): IndexedValue<T> {
        val currentIndex = index
        index += 1
        if (currentIndex < 0) {
            throw ArithmeticException("Index overflow has happened.")
        }
        return IndexedValue(currentIndex, source.next())
    }
}

internal class IndexingIterable<out T>(
    private val source: Iterable<T>
) : Iterable<IndexedValue<T>> {
    override fun iterator(): Iterator<IndexedValue<T>> = IndexingIterator(source.iterator())
}

public fun <T> Iterable<T>.withIndex(): Iterable<IndexedValue<T>> {
    return IndexingIterable(this)
}

public inline fun <T> Iterator<T>.forEach(operation: (T) -> Unit): Unit {
    while (hasNext()) {
        operation(next())
    }
}

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
