/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/Tuples.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-874: `Pair` owns its public constructor in this source-backed declaration.
// Pair values remain runtime boxes because collection and sequence bridges create
// the same representation; the allocating bridge is therefore intentionally kept.

/**
 * Represents a generic pair of two values.
 */
public class Pair<out A, out B> {
    @KsSymbolName("__kk_pair_new")
    public constructor(first: A, second: B)

    @KsSymbolName("__kk_pair_first")
    private external fun firstComponent(): A

    @KsSymbolName("__kk_pair_second")
    private external fun secondComponent(): B

    /** First value. */
    public val first: A
        get() = firstComponent()

    /** Second value. */
    public val second: B
        get() = secondComponent()

    public operator fun component1(): A = first

    public operator fun component2(): B = second

    override fun equals(other: Any?): Boolean {
        val o = other as? Pair<*, *> ?: return false
        return first == o.first && second == o.second
    }

    override fun hashCode(): Int = 31 * (first?.hashCode() ?: 0) + (second?.hashCode() ?: 0)

    /** Returns string representation of the [Pair] including its [first] and [second] values. */
    override fun toString(): String = "($first, $second)"

    /** Converts this pair into a list. */
    public fun toList(): List<Any?> = listOf(first, second)
}
