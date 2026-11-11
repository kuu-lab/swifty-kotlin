/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/common/src/generated/_Arrays.kt.
 */

package kotlin.collections

import kotlin.comparisons.compareValues
import kotlin.comparisons.naturalOrder
import kotlin.comparisons.reverseOrder

@SinceKotlin("2.4")
public fun <T : Comparable<T>> Array<out T>.isSorted(): Boolean =
    isSortedWith(naturalOrder<T>())

@SinceKotlin("2.4")
public fun <T : Comparable<T>> Array<out T>.isSortedDescending(): Boolean =
    isSortedWith(reverseOrder<T>())

@SinceKotlin("2.4")
public fun <T> Array<out T>.isSortedWith(comparator: Comparator<in T>): Boolean {
    var index = 1
    while (index < size) {
        if (comparator.compare(this[index - 1], this[index]) > 0) return false
        index += 1
    }
    return true
}

@SinceKotlin("2.4")
public inline fun <T, R : Comparable<R>> Array<out T>.isSortedBy(selector: (T) -> R?): Boolean {
    if (size < 2) return true
    var previous = selector(this[0])
    var index = 1
    while (index < size) {
        val current = selector(this[index])
        if (compareValues(previous, current) > 0) return false
        previous = current
        index += 1
    }
    return true
}

@SinceKotlin("2.4")
public inline fun <T, R : Comparable<R>> Array<out T>.isSortedByDescending(selector: (T) -> R?): Boolean {
    if (size < 2) return true
    var previous = selector(this[0])
    var index = 1
    while (index < size) {
        val current = selector(this[index])
        if (compareValues(previous, current) < 0) return false
        previous = current
        index += 1
    }
    return true
}
