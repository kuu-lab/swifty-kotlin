/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/Tuples.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-608: `Pair`/`Triple` class bodies are Kotlin source. Their instances stay
// runtime boxes because the runtime hands out the very same boxes for
// zip / associate / withIndex / Map.Entry, so allocation and component reads
// remain bridges while the rest of the surface is ordinary Kotlin.

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

    /** Returns string representation of the [Pair] including its [first] and [second] values. */
    override fun toString(): String = "($first, $second)"

    /** Converts this pair into a list. */
    public fun toList(): List<Any?> = listOf(first, second)
}

/**
 * Represents a triad of values.
 */
public class Triple<out A, out B, out C> {
    @KsSymbolName("__kk_triple_new")
    public constructor(first: A, second: B, third: C)

    @KsSymbolName("__kk_triple_first")
    private external fun firstComponent(): A

    @KsSymbolName("__kk_triple_second")
    private external fun secondComponent(): B

    @KsSymbolName("__kk_triple_third")
    private external fun thirdComponent(): C

    /** First value. */
    public val first: A
        get() = firstComponent()

    /** Second value. */
    public val second: B
        get() = secondComponent()

    /** Third value. */
    public val third: C
        get() = thirdComponent()

    public operator fun component1(): A = first

    public operator fun component2(): B = second

    public operator fun component3(): C = third

    /** Returns string representation of the [Triple] including its [first], [second] and [third] values. */
    override fun toString(): String = "($first, $second, $third)"

    /** Converts this triple into a list. */
    public fun toList(): List<Any?> = listOf(first, second, third)
}
