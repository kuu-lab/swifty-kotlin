package kotlin.time

@JvmInline
public value class Duration private constructor(private val rawValue: Long) : Comparable<Duration> {
    public val inWholeNanoseconds: Long get() = toLong(DurationUnit.NANOSECONDS)
    public val inWholeMicroseconds: Long get() = toLong(DurationUnit.MICROSECONDS)
    public val inWholeMilliseconds: Long get() = toLong(DurationUnit.MILLISECONDS)
    public val inWholeSeconds: Long get() = toLong(DurationUnit.SECONDS)
    public val inWholeMinutes: Long get() = toLong(DurationUnit.MINUTES)
    public val inWholeHours: Long get() = toLong(DurationUnit.HOURS)
    public val inWholeDays: Long get() = toLong(DurationUnit.DAYS)

    @PublishedApi
    internal val nanosecondsComponent: Int
        get() {
            if (isInfinite()) return 0
            val scale = durationStorageScale(rawValue)
            return ((durationValue(rawValue) % (NANOS_PER_SECOND / scale)) * scale).toInt()
        }

    public fun isNegative(): Boolean = rawValue < 0L
    public fun isPositive(): Boolean = rawValue > 0L
    public fun isInfinite(): Boolean = durationIsInfinite(rawValue)
    public fun isFinite(): Boolean = !isInfinite()

    public override fun compareTo(other: Duration): Int = compareDurationRaw(rawValue, other.rawValue)

    public operator fun plus(other: Duration): Duration = Duration(addDurationRaw(rawValue, other.rawValue))

    public operator fun minus(other: Duration): Duration = this + (-other)

    public operator fun unaryMinus(): Duration = negated()

    internal fun negated(): Duration = Duration(((-durationValue(rawValue)) shl 1) or (rawValue and 1L))

    public override fun toString(): String = durationToString(rawValue)

    public fun toDouble(unit: DurationUnit): Double = durationRawToDouble(rawValue, unit)

    public fun toLong(unit: DurationUnit): Long = durationRawToLong(rawValue, unit)

    public fun toInt(unit: DurationUnit): Int {
        val wholeValue = toLong(unit)
        return if (wholeValue < Int.MIN_VALUE.toLong()) Int.MIN_VALUE
            else if (wholeValue > Int.MAX_VALUE.toLong()) Int.MAX_VALUE
            else wholeValue.toInt()
    }

    public companion object {
        public val ZERO: Duration get() = Duration(0L)
        public val INFINITE: Duration get() = Duration(Long.MAX_VALUE)

        internal fun fromRawValue(rawValue: Long): Duration = Duration(rawValue)
    }
}

public fun Int.toDuration(unit: DurationUnit): Duration = Duration.fromRawValue(durationRawFromLong(this.toLong(), unit))

public fun Long.toDuration(unit: DurationUnit): Duration = Duration.fromRawValue(durationRawFromLong(this, unit))

public fun Double.toDuration(unit: DurationUnit): Duration = Duration.fromRawValue(durationRawFromDouble(this, durationUnitScale(unit)))
