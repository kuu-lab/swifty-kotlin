/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/common/src/generated/_Collections.kt.
 */

package kotlin.collections

import kotlin.comparisons.compareValues
import kotlin.comparisons.naturalOrder
import kotlin.comparisons.reverseOrder

@SinceKotlin("2.4")
public fun <T : Comparable<T>> Iterable<T>.isSorted(): Boolean =
    isSortedWith(naturalOrder<T>())

@SinceKotlin("2.4")
public fun <T : Comparable<T>> Iterable<T>.isSortedDescending(): Boolean =
    isSortedWith(reverseOrder<T>())

@SinceKotlin("2.4")
public fun <T> Iterable<T>.isSortedWith(comparator: Comparator<in T>): Boolean =
    iterator().isSortedWithComparator(comparator)

@SinceKotlin("2.4")
public inline fun <T, R : Comparable<R>> Iterable<T>.isSortedBy(selector: (T) -> R?): Boolean =
    iterator().isSortedBySelector(false, selector)

@SinceKotlin("2.4")
public inline fun <T, R : Comparable<R>> Iterable<T>.isSortedByDescending(selector: (T) -> R?): Boolean =
    iterator().isSortedBySelector(true, selector)

internal fun <T> Iterator<T>.isSortedWithComparator(comparator: Comparator<in T>): Boolean {
    if (!hasNext()) return true
    var previous = next()
    while (hasNext()) {
        val current = next()
        if (comparator.compare(previous, current) > 0) return false
        previous = current
    }
    return true
}

@PublishedApi
internal inline fun <T, R : Comparable<R>> Iterator<T>.isSortedBySelector(
    descending: Boolean,
    selector: (T) -> R?
): Boolean {
    if (!hasNext()) return true
    val first = next()
    // Check for a second element before invoking the selector, even for a lazy iterator.
    if (!hasNext()) return true
    var previous = selector(first)
    while (hasNext()) {
        val current = selector(next())
        val order = compareValues(previous, current)
        if (if (descending) order < 0 else order > 0) return false
        previous = current
    }
    return true
}
