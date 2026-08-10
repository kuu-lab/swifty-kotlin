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
// The members (`start`, `endInclusive`, `endExclusive`, `contains`, `isEmpty`,
// `lessThanOrEquals`) stay compiler residuals, alongside the concrete
// `IntRange`/`LongRange`/`CharRange`/`UIntRange`/`ULongRange` conformances that
// are wired before bundled headers are collected. Declaring them here instead
// turns every interface-typed member call into an itable dispatch that the
// pre-bundle conformance wiring cannot populate. Moving them to Kotlin belongs
// with the concrete conformance rework (KSP-451).

/**
 * Represents a range of values of type [T] with both bounds included in the range.
 */
public interface ClosedRange<T : Comparable<T>>

/**
 * Represents a range of [Comparable] values with the upper bound excluded from the range.
 */
public interface OpenEndRange<T : Comparable<T>>

/**
 * Represents a range of floating point numbers, where `lessThanOrEquals` keeps the
 * IEEE 754 ordering of the bounds.
 */
public interface ClosedFloatingPointRange<T : Comparable<T>> : ClosedRange<T>
