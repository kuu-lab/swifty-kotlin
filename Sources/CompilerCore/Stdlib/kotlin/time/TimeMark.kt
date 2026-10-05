package kotlin.time

// KSP-648
// TimeMark operations dispatch to the mark's own time source. Only Monotonic
// samples the native clock through timeMarkElapsedNanos.
//
// Reading arithmetic saturates at Long.MIN_VALUE/Long.MAX_VALUE, matching the previous
// native implementation so that shifting a mark by Duration.INFINITE stays well defined.

import kotlin.internal.KsSymbolName

public interface TimeMark {
    public fun elapsedNow(): Duration

    public fun hasPassedNow(): Boolean = !elapsedNow().isNegative()

    public fun hasNotPassedNow(): Boolean = elapsedNow().isNegative()

    public operator fun plus(duration: Duration): TimeMark = AdjustedTimeMark(this, duration)

    public operator fun minus(duration: Duration): TimeMark = plus(-duration)
}

private class AdjustedTimeMark(private val mark: TimeMark, private val adjustment: Duration) : TimeMark {
    override fun elapsedNow(): Duration = this.mark.elapsedNow().__kk_duration_minus(this.adjustment)

    override fun plus(duration: Duration): TimeMark =
        AdjustedTimeMark(this.mark, this.adjustment.__kk_duration_plus(duration))
}

@KsSymbolName("__kk_time_mark_now_reading_nanos")
private external fun __kk_time_mark_now_reading_nanos(): Long

internal fun timeMarkNegateNanos(value: Long): Long =
    if (value == Long.MIN_VALUE) Long.MAX_VALUE else -value

internal fun timeMarkAddNanos(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}

internal fun timeMarkElapsedNanos(readingNanos: Long): Long =
    timeMarkAddNanos(__kk_time_mark_now_reading_nanos(), timeMarkNegateNanos(readingNanos))
