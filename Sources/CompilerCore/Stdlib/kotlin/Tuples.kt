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
//
// Upstream declares both as `data class`es. Here they are plain classes: a data
// class stores its constructor parameters in the object's own layout, whereas
// these are views over a `RuntimePairBox`/`RuntimeTripleBox` whose fields are
// read back through the component bridges. `equals`/`hashCode` are therefore
// written out by hand instead of generated, matching what the data class
// modifier would emit. The allocation bridges tag those boxes with the nominal
// type ID of `kotlin.Pair`/`kotlin.Triple`, which is what lets the safe casts
// below succeed and what the runtime's own equality/hash fallbacks key on for
// tuples reaching them through `Any`.

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

/**
 * Creates a tuple of type [Pair] from this and [that].
 */
public inline infix fun <A, B> A.to(that: B): Pair<A, B> = Pair(this, that)

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

    override fun equals(other: Any?): Boolean {
        val o = other as? Triple<*, *, *> ?: return false
        return first == o.first && second == o.second && third == o.third
    }

    override fun hashCode(): Int =
        31 * (31 * (first?.hashCode() ?: 0) + (second?.hashCode() ?: 0)) + (third?.hashCode() ?: 0)

    /** Returns string representation of the [Triple] including its [first], [second] and [third] values. */
    override fun toString(): String = "($first, $second, $third)"

    /** Converts this triple into a list. */
    public fun toList(): List<Any?> = listOf(first, second, third)
}
