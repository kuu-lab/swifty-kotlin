/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/Tuples.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

// `Pair`/`Triple` instances stay runtime boxes because the runtime hands out the
// very same boxes for zip / associate / withIndex / Map.Entry, so allocation and
// component reads remain bridges while the rest of the surface is ordinary Kotlin.
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

public inline infix fun <A, B> A.to(that: B): Pair<A, B> = Pair(this, that)

public class Triple<out A, out B, out C> {
    @KsSymbolName("__kk_triple_new")
    public constructor(first: A, second: B, third: C)

    @KsSymbolName("__kk_triple_first")
    private external fun firstComponent(): A

    @KsSymbolName("__kk_triple_second")
    private external fun secondComponent(): B

    @KsSymbolName("__kk_triple_third")
    private external fun thirdComponent(): C

    public val first: A
        get() = firstComponent()

    public val second: B
        get() = secondComponent()

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

    override fun toString(): String = "($first, $second, $third)"

    public fun toList(): List<Any?> = listOf(first, second, third)
}

public fun <A, B, C> Triple<A, B, C>.copy(
    first: A = this.first,
    second: B = this.second,
    third: C = this.third
): Triple<A, B, C> = Triple(first, second, third)
