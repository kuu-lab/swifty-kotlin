/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/ranges/Range.kt.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-1311: the `OpenEndRange<T>` member declarations are source-backed here,
// moved out of Ranges.kt alongside the interface itself. The declaration still
// reuses the synthetic shell registered by
// `HeaderHelpers+SyntheticRangeProgressionStubs.swift`, so `rangeUntil` and the
// concrete range conformances wired before bundled header collection keep
// resolving to the same nominal symbol.
//
// Runtime range values (`1..<5`, `x..<y`) are opaque `RuntimeRangeBox` handles
// that do not register interface itables, so interface-typed member access
// cannot dispatch through `.itableDynamic`. The `start`/`endExclusive`
// properties therefore stay source-declared but keep their residual synthetic
// `__kk_range_first`/`__kk_range_endExclusive` external links (the same
// `Map.size` pattern), while `contains`/`isEmpty` bind the call sites
// directly through `@KsSymbolName` like `Set.isEmpty`/`Map.isEmpty`.

/**
 * Represents a range of [Comparable] values with the upper bound excluded from the range.
 */
public interface OpenEndRange<T : Comparable<T>> {
    /**
     * The minimum value in the range.
     */
    public val start: T

    /**
     * The maximum value in the range (exclusive).
     *
     * @throws IllegalStateException can be thrown if the exclusive end bound cannot be represented
     * with a value of type [T].
     */
    public val endExclusive: T

    /**
     * Checks whether the specified [value] belongs to the range.
     */
    @KsSymbolName("__kk_range_contains")
    public operator fun contains(value: T): Boolean

    /**
     * Checks whether the range is empty.
     */
    @KsSymbolName("__kk_range_isEmpty")
    public fun isEmpty(): Boolean
}
