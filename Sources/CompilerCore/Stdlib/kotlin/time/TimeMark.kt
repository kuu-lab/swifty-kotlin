package kotlin.time

// KSP-648
// TimeMark / ComparableTimeMark operations.
// Migration source: Sources/Runtime/RuntimeTime.swift
//   kk_time_mark_elapsed_now, kk_time_mark_has_passed_now, kk_time_mark_has_not_passed_now,
//   kk_time_mark_plus_duration, kk_time_mark_minus_duration, kk_time_mark_minus_mark,
//   kk_time_mark_compare
//
// Only the mark's monotonic reading stays native: __kk_time_mark_reading_nanos reads the
// nanosecond reading captured by markNow(), __kk_time_mark_now_reading_nanos samples the
// monotonic clock, and the two *_from_reading_nanos factories allocate a shifted mark
// (TimeMark and ComparableTimeMark are distinct nominal types, hence two factories).
// Everything else is Duration arithmetic here.
//
// Reading arithmetic saturates at Long.MIN_VALUE/Long.MAX_VALUE, matching the previous
// native implementation so that shifting a mark by Duration.INFINITE stays well defined.

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_time_mark_reading_nanos")
private external fun __kk_time_mark_reading_nanos(mark: Any): Long

@KsSymbolName("__kk_time_mark_now_reading_nanos")
private external fun __kk_time_mark_now_reading_nanos(): Long

@KsSymbolName("__kk_time_mark_from_reading_nanos")
private external fun __kk_time_mark_from_reading_nanos(readingNanos: Long): TimeMark

@KsSymbolName("__kk_comparable_time_mark_from_reading_nanos")
private external fun __kk_comparable_time_mark_from_reading_nanos(readingNanos: Long): ComparableTimeMark

internal fun timeMarkNegateNanos(value: Long): Long =
    if (value == Long.MIN_VALUE) Long.MAX_VALUE else -value

internal fun timeMarkAddNanos(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}

internal fun timeMarkElapsedNanos(readingNanos: Long): Long =
    timeMarkAddNanos(__kk_time_mark_now_reading_nanos(), timeMarkNegateNanos(readingNanos))

public fun TimeMark.elapsedNow(): Duration =
    timeMarkElapsedNanos(__kk_time_mark_reading_nanos(this)).nanoseconds

public fun TimeMark.hasPassedNow(): Boolean = !this.elapsedNow().isNegative()

public fun TimeMark.hasNotPassedNow(): Boolean = this.elapsedNow().isNegative()

public operator fun TimeMark.plus(duration: Duration): TimeMark =
    __kk_time_mark_from_reading_nanos(
        timeMarkAddNanos(__kk_time_mark_reading_nanos(this), duration.inWholeNanoseconds)
    )

public operator fun TimeMark.minus(duration: Duration): TimeMark = this + (-duration)

public fun ComparableTimeMark.elapsedNow(): Duration =
    timeMarkElapsedNanos(__kk_time_mark_reading_nanos(this)).nanoseconds

public fun ComparableTimeMark.hasPassedNow(): Boolean = !this.elapsedNow().isNegative()

public fun ComparableTimeMark.hasNotPassedNow(): Boolean = this.elapsedNow().isNegative()

public operator fun ComparableTimeMark.plus(duration: Duration): ComparableTimeMark =
    __kk_comparable_time_mark_from_reading_nanos(
        timeMarkAddNanos(__kk_time_mark_reading_nanos(this), duration.inWholeNanoseconds)
    )

public operator fun ComparableTimeMark.minus(duration: Duration): ComparableTimeMark =
    this + (-duration)

public operator fun ComparableTimeMark.minus(other: ComparableTimeMark): Duration =
    timeMarkAddNanos(
        __kk_time_mark_reading_nanos(this),
        timeMarkNegateNanos(__kk_time_mark_reading_nanos(other))
    ).nanoseconds

public operator fun ComparableTimeMark.compareTo(other: ComparableTimeMark): Int =
    (this - other).compareTo(Duration.ZERO)
