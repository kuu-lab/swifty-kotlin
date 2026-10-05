/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/ranges/Ranges.kt.
 */

package kotlin.ranges

// KSP-652: the nominal `ClosedRange`/`ClosedFloatingPointRange`/`OpenEndRange`
// declarations migrated out of the synthetic self-registration; on bundle load
// they reuse the synthetic shells registered by
// `HeaderHelpers+SyntheticRangeInterfaceStubs.swift` /
// `HeaderHelpers+SyntheticRangeProgressionStubs.swift`.
//
// KSP-1311 moved the `OpenEndRange` declaration and its `start`/`endExclusive`/
// `contains`/`isEmpty` members into `OpenEndRange/OpenEndRange.kt` (runtime
// `__kk_range_*` links retained — the range boxes have no interface itables).
// ClosedFloatingPointRange members remain compiler residuals.
// Typed range class shells are source-backed by IntRange.kt, LongRange.kt, and
// CharRange.kt; unsigned range shells are source-backed by
// UIntRange/Stdlib.kt and ULongRange/Stdlib.kt (KSP-709).

/**
 * Represents a range of floating point numbers, where `lessThanOrEquals` keeps the
 * IEEE 754 ordering of the bounds.
 */
public interface ClosedFloatingPointRange<T : Comparable<T>> : ClosedRange<T>
