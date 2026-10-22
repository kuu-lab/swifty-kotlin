/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/ranges/Ranges.kt.
 */

package kotlin.ranges

// KUU-763: the `ClosedFloatingPointRange<T>` member declarations are
// source-backed here, moved out of Ranges.kt alongside the interface itself.
//
// Runtime range values (`1.0..2.0`, `x..<y`) are opaque
// `RuntimeDoubleRangeBox`/`RuntimeFloatRangeBox` handles that do not register
// interface itables, so interface-typed member calls cannot dispatch through
// `.itableDynamic`. `contains`/`isEmpty`/`lessThanOrEquals` therefore keep the
// `__kk_floating_range_*_or_null` runtime probes in front of the itable
// fallback (the same pattern as the `start`/`endInclusive` endpoint probe in
// `emitRuntimeFloatingPointEndpointFastPath`), while user-defined
// implementations dispatch through the itable to these bodies/overrides.

public interface ClosedFloatingPointRange<T : Comparable<T>> : ClosedRange<T> {
    public override operator fun contains(value: T): Boolean =
        lessThanOrEquals(start, value) && lessThanOrEquals(value, endInclusive)

    public override fun isEmpty(): Boolean = !lessThanOrEquals(start, endInclusive)

    public fun lessThanOrEquals(a: T, b: T): Boolean
}
