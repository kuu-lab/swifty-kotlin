package kotlin.time

// MIGRATION-TIME-001
// Duration arithmetic and predicates.
// Migration source: Sources/Runtime/RuntimeDuration.swift
//   kk_duration_plus, kk_duration_minus, kk_duration_times_int, kk_duration_div_int,
//   kk_duration_div_duration, kk_duration_unary_minus, kk_duration_absoluteValue,
//   kk_duration_isNegative, kk_duration_isPositive, kk_duration_isInfinite
//
// All operations delegate to __kk_duration_* bridges backed by kk_* ABI functions.
// Bridge stubs are registered in HeaderHelpers+SyntheticDurationStubs.swift.

public operator fun Duration.plus(other: Duration): Duration =
    this.__kk_duration_plus(other)

public operator fun Duration.minus(other: Duration): Duration =
    this.__kk_duration_minus(other)

public operator fun Duration.times(scale: Int): Duration =
    this.__kk_duration_times_int(scale)

public operator fun Duration.div(scale: Int): Duration =
    this.__kk_duration_div_int(scale)

public operator fun Duration.div(other: Duration): Double =
    this.__kk_duration_div_duration(other)

public operator fun Duration.unaryMinus(): Duration =
    this.__kk_duration_unary_minus()

public val Duration.absoluteValue: Duration
    get() = this.__kk_duration_absoluteValue()

public fun Duration.isNegative(): Boolean = this.__kk_duration_isNegative()

public fun Duration.isPositive(): Boolean = this.__kk_duration_isPositive()

public fun Duration.isInfinite(): Boolean = this.__kk_duration_isInfinite()
