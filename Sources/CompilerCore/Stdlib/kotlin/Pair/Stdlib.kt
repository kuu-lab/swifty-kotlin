/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/Tuples.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-874: Pair values remain runtime boxes because collection and sequence
// bridges create the same representation; the allocating bridge is therefore
// intentionally kept.

public class Pair<out A, out B> {
    @KsSymbolName("__kk_pair_new")
    public constructor(first: A, second: B)

    @KsSymbolName("__kk_pair_first")
    private external fun firstComponent(): A

    @KsSymbolName("__kk_pair_second")
    private external fun secondComponent(): B

    @KsSymbolName("__kk_pair_first")
    public val first: A
        get() = firstComponent()

    public val second: B
        get() = secondComponent()

    public operator fun component1(): A = first

    public operator fun component2(): B = second

    override fun equals(other: Any?): Boolean {
        val o = other as? Pair<*, *> ?: return false
        return first == o.first && second == o.second
    }

    override fun hashCode(): Int = 31 * (first?.hashCode() ?: 0) + (second?.hashCode() ?: 0)

    override fun toString(): String = "($first, $second)"

    public fun toList(): List<Any?> = listOf(first, second)
}
