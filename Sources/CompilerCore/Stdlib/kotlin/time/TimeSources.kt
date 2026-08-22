package kotlin.time

// KSP-650
// AbstractLongTimeSource, AbstractDoubleTimeSource, and TestTimeSource.
// The implementation follows Kotlin 2.3.10's TimeSources.kt. Only the
// platform-independent time reading and Duration conversion primitives remain
// behind the existing runtime-backed stdlib surface.

private fun timeSourceDurationFromLong(value: Long, unit: DurationUnit): Duration {
    return value.toDuration(unit)
}

private fun timeSourceDurationFromDouble(value: Double, unit: DurationUnit): Duration {
    return value.toDuration(unit)
}

private fun timeSourceDurationIsInfinite(duration: Duration): Boolean =
    duration.__kk_duration_isInfinite()

private fun timeSourceDurationIsNegative(duration: Duration): Boolean =
    duration.__kk_duration_isNegative()

private fun timeSourceDurationPlus(lhs: Duration, rhs: Duration): Duration =
    lhs.__kk_duration_plus(rhs)

private fun timeSourceDurationMinus(lhs: Duration, rhs: Duration): Duration =
    lhs.__kk_duration_minus(rhs)

private fun timeSourceDurationCompare(lhs: Duration, rhs: Duration): Int =
    lhs.__kk_duration_compareTo(rhs)

private fun timeSourceDurationZero(): Duration = __kk_duration_zero()

private fun timeSourceUnitScale(unit: DurationUnit): Long = when (unit) {
    DurationUnit.NANOSECONDS -> 1L
    DurationUnit.MICROSECONDS -> 1_000L
    DurationUnit.MILLISECONDS -> 1_000_000L
    DurationUnit.SECONDS -> 1_000_000_000L
    DurationUnit.MINUTES -> 60_000_000_000L
    DurationUnit.HOURS -> 3_600_000_000_000L
    DurationUnit.DAYS -> 86_400_000_000_000L
}

private fun timeSourceDurationToLong(duration: Duration, unit: DurationUnit): Long {
    if (timeSourceDurationIsInfinite(duration)) {
        return if (timeSourceDurationIsNegative(duration)) Long.MIN_VALUE else Long.MAX_VALUE
    }
    return duration.inWholeNanoseconds / timeSourceUnitScale(unit)
}

private fun timeSourceTruncateTo(duration: Duration, unit: DurationUnit): Duration =
    timeSourceDurationFromLong(timeSourceDurationToLong(duration, unit), unit)

private fun timeSourceSaturatingAdd(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}

private fun timeSourceSaturatingSubtract(lhs: Long, rhs: Long): Long {
    if (rhs == Long.MIN_VALUE) {
        return if (lhs >= 0L) Long.MAX_VALUE else timeSourceSaturatingAdd(lhs, Long.MAX_VALUE) + 1L
    }
    return timeSourceSaturatingAdd(lhs, -rhs)
}

private fun timeSourceUnitDifference(lhs: Long, rhs: Long, unit: DurationUnit): Duration =
    timeSourceDurationFromLong(timeSourceSaturatingSubtract(lhs, rhs), unit)

private fun timeSourceUnitAdd(lhs: Long, duration: Duration, unit: DurationUnit): Long =
    timeSourceSaturatingAdd(lhs, timeSourceDurationToLong(duration, unit))

private fun timeSourceUnitShortName(unit: DurationUnit): String = when (unit) {
    DurationUnit.NANOSECONDS -> "ns"
    DurationUnit.MICROSECONDS -> "us"
    DurationUnit.MILLISECONDS -> "ms"
    DurationUnit.SECONDS -> "s"
    DurationUnit.MINUTES -> "min"
    DurationUnit.HOURS -> "h"
    DurationUnit.DAYS -> "d"
}

public abstract class AbstractLongTimeSource protected constructor(
    unit: DurationUnit
) : TimeSource.WithComparableMarks {
    protected val unit: DurationUnit = unit

    protected open abstract fun read(): Long

    internal var zeroInitialized: Boolean = false
    internal var zero: Duration = timeSourceDurationZero()

    internal fun adjustedRead(): Long {
        val current = read()
        if (!zeroInitialized) {
            zero = timeSourceDurationFromLong(current, unit)
            zeroInitialized = true
        }
        return timeSourceSaturatingSubtract(current, timeSourceDurationToLong(zero, unit))
    }

    internal fun timeSourceUnit(): DurationUnit = unit

    override fun markNow(): ComparableTimeMark = AbstractLongTimeMark(adjustedRead(), this, timeSourceDurationZero())
}

public abstract class AbstractDoubleTimeSource protected constructor(
    unit: DurationUnit
) : TimeSource.WithComparableMarks {
    protected val unit: DurationUnit = unit

    protected open abstract fun read(): Double

    internal fun currentReading(): Double = read()

    internal fun timeSourceUnit(): DurationUnit = unit

    override fun markNow(): ComparableTimeMark = AbstractDoubleTimeMark(currentReading(), this, timeSourceDurationZero())
}

internal class AbstractLongTimeMark(
    startedAt: Long,
    timeSource: AbstractLongTimeSource,
    offset: Duration
) : ComparableTimeMark {
    public val startedAtValue: Long = startedAt
    private val timeSourceValue: AbstractLongTimeSource = timeSource
    public val offsetValue: Duration = offset

    override fun elapsedNow(): Duration =
        timeSourceDurationMinus(
            timeSourceUnitDifference(
                this.timeSourceValue.adjustedRead(),
                this.startedAtValue,
                this.timeSourceValue.timeSourceUnit()
            ),
            this.offsetValue
        )

    override fun plus(duration: Duration): ComparableTimeMark {
        if (timeSourceDurationIsInfinite(duration)) {
            return AbstractLongTimeMark(
                timeSourceUnitAdd(this.startedAtValue, duration, this.timeSourceValue.timeSourceUnit()),
                this.timeSourceValue,
                timeSourceDurationZero()
            )
        }

        val durationInUnit = timeSourceTruncateTo(duration, this.timeSourceValue.timeSourceUnit())
        val rest = timeSourceDurationPlus(
            timeSourceDurationMinus(duration, durationInUnit),
            this.offsetValue
        )
        var sum = timeSourceUnitAdd(this.startedAtValue, durationInUnit, this.timeSourceValue.timeSourceUnit())
        val restInUnit = timeSourceTruncateTo(rest, this.timeSourceValue.timeSourceUnit())
        sum = timeSourceUnitAdd(sum, restInUnit, this.timeSourceValue.timeSourceUnit())
        var restUnderUnit = timeSourceDurationMinus(rest, restInUnit)
        val restUnderUnitNs = restUnderUnit.inWholeNanoseconds
        val oppositeSigns = (sum > 0L && restUnderUnitNs < 0L) ||
            (sum < 0L && restUnderUnitNs > 0L)
        if (sum != 0L && restUnderUnitNs != 0L && oppositeSigns) {
            val correction = if (restUnderUnitNs < 0L) {
                timeSourceDurationFromLong(-1L, this.timeSourceValue.timeSourceUnit())
            } else {
                timeSourceDurationFromLong(1L, this.timeSourceValue.timeSourceUnit())
            }
            sum = timeSourceUnitAdd(sum, correction, this.timeSourceValue.timeSourceUnit())
            restUnderUnit = timeSourceDurationMinus(restUnderUnit, correction)
        }
        val newOffset = if (sum == Long.MIN_VALUE || sum == Long.MAX_VALUE) {
            timeSourceDurationZero()
        } else {
            restUnderUnit
        }
        return AbstractLongTimeMark(sum, this.timeSourceValue, newOffset)
    }

    override fun minus(other: ComparableTimeMark): Duration {
        if (other !is AbstractLongTimeMark || this.timeSourceValue !== other.timeSourceValue) {
            throw IllegalArgumentException(
                "Subtracting or comparing time marks from different time sources is not possible: $this and $other"
            )
        }
        val otherMark = other as AbstractLongTimeMark
        return timeSourceDurationPlus(
            timeSourceUnitDifference(
                this.startedAtValue,
                otherMark.startedAtValue,
                this.timeSourceValue.timeSourceUnit()
            ),
            timeSourceDurationMinus(this.offsetValue, otherMark.offsetValue)
        )
    }

    override fun equals(other: Any?): Boolean =
        other is AbstractLongTimeMark && this.timeSourceValue === other.timeSourceValue &&
            timeSourceDurationCompare(this.minus(other), timeSourceDurationZero()) == 0

    override fun hashCode(): Int = this.offsetValue.hashCode() * 37 + this.startedAtValue.hashCode()

    override fun toString(): String =
        "LongTimeMark(${this.startedAtValue}${timeSourceUnitShortName(this.timeSourceValue.timeSourceUnit())} + ${this.offsetValue}, ${this.timeSourceValue})"
}

internal class AbstractDoubleTimeMark(
    startedAt: Double,
    timeSource: AbstractDoubleTimeSource,
    offset: Duration
) : ComparableTimeMark {
    public val startedAtValue: Double = startedAt
    private val timeSourceValue: AbstractDoubleTimeSource = timeSource
    public val offsetValue: Duration = offset

    override fun elapsedNow(): Duration =
        timeSourceDurationMinus(
            timeSourceDurationFromDouble(
                this.timeSourceValue.currentReading() - this.startedAtValue,
                this.timeSourceValue.timeSourceUnit()
            ),
            this.offsetValue
        )

    override fun plus(duration: Duration): ComparableTimeMark =
        AbstractDoubleTimeMark(this.startedAtValue, this.timeSourceValue, timeSourceDurationPlus(this.offsetValue, duration))

    override fun minus(other: ComparableTimeMark): Duration {
        if (other !is AbstractDoubleTimeMark || this.timeSourceValue !== other.timeSourceValue) {
            throw IllegalArgumentException(
                "Subtracting or comparing time marks from different time sources is not possible: $this and $other"
            )
        }
        val otherMark = other as AbstractDoubleTimeMark
        return timeSourceDurationPlus(
            timeSourceDurationFromDouble(
                this.startedAtValue - otherMark.startedAtValue,
                this.timeSourceValue.timeSourceUnit()
            ),
            timeSourceDurationMinus(this.offsetValue, otherMark.offsetValue)
        )
    }

    override fun equals(other: Any?): Boolean =
        other is AbstractDoubleTimeMark && this.timeSourceValue === other.timeSourceValue &&
            timeSourceDurationCompare(this.minus(other), timeSourceDurationZero()) == 0

    override fun hashCode(): Int = timeSourceDurationPlus(
        timeSourceDurationFromDouble(this.startedAtValue, this.timeSourceValue.timeSourceUnit()),
        this.offsetValue
    ).hashCode()

    override fun toString(): String =
        "DoubleTimeMark(${this.startedAtValue}${timeSourceUnitShortName(this.timeSourceValue.timeSourceUnit())} + ${this.offsetValue}, ${this.timeSourceValue})"
}

public class TestTimeSource : AbstractLongTimeSource(DurationUnit.NANOSECONDS) {
    internal var reading: Duration = timeSourceDurationZero()

    init {
        markNow()
    }

    override fun read(): Long = reading.inWholeNanoseconds

    public operator fun plusAssign(duration: Duration) {
        if (timeSourceDurationIsInfinite(duration)) {
            overflow(duration)
        }
        val delta = timeSourceDurationToLong(duration, unit)
        val current = reading.inWholeNanoseconds
        if ((delta > 0L && current > Long.MAX_VALUE - delta) ||
            (delta < 0L && current < Long.MIN_VALUE - delta)
        ) {
            overflow(duration)
        }
        reading = timeSourceDurationFromLong(current + delta, unit)
    }

    private fun overflow(duration: Duration): Nothing =
        throw IllegalStateException(
            "TestTimeSource will overflow if its reading ${read()}${timeSourceUnitShortName(unit)} is advanced by $duration."
        )
}
