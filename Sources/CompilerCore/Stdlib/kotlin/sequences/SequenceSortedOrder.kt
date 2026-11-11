/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/common/src/generated/_Sequences.kt.
 */

package kotlin.sequences

import kotlin.collections.isSortedBySelector
import kotlin.collections.isSortedWithComparator
import kotlin.comparisons.naturalOrder
import kotlin.comparisons.reverseOrder

// These terminal operations consume only as much of the sequence as needed.
@SinceKotlin("2.4")
public fun <T : Comparable<T>> Sequence<T>.isSorted(): Boolean =
    isSortedWith(naturalOrder<T>())

@SinceKotlin("2.4")
public fun <T : Comparable<T>> Sequence<T>.isSortedDescending(): Boolean =
    isSortedWith(reverseOrder<T>())

@SinceKotlin("2.4")
public fun <T> Sequence<T>.isSortedWith(comparator: Comparator<in T>): Boolean =
    iterator().isSortedWithComparator(comparator)

@SinceKotlin("2.4")
public inline fun <T, R : Comparable<R>> Sequence<T>.isSortedBy(selector: (T) -> R?): Boolean =
    iterator().isSortedBySelector(false, selector)

@SinceKotlin("2.4")
public inline fun <T, R : Comparable<R>> Sequence<T>.isSortedByDescending(selector: (T) -> R?): Boolean =
    iterator().isSortedBySelector(true, selector)
