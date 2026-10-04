/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/ranges/Range.kt.
 */

package kotlin.ranges

public interface ClosedRange<T : Comparable<T>> {
    public val start: T
    public val endInclusive: T

    public operator fun contains(value: T): Boolean = value >= start && value <= endInclusive

    public fun isEmpty(): Boolean = start > endInclusive
}
