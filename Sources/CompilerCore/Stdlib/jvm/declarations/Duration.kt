package kotlin.time

@JvmInline
public value class Duration internal constructor(private val rawValue: Long) : Comparable<Duration> {
    public val inWholeNanoseconds: Long get() = 0L
    public val inWholeMicroseconds: Long get() = 0L
    public val inWholeMilliseconds: Long get() = 0L
    public val inWholeSeconds: Long get() = 0L
    public val inWholeMinutes: Long get() = 0L
    public val inWholeHours: Long get() = 0L
    public val inWholeDays: Long get() = 0L

    public fun isNegative(): Boolean = false
    public fun isPositive(): Boolean = false
    public fun isInfinite(): Boolean = false
    public fun isFinite(): Boolean = false
    public override fun compareTo(other: Duration): Int = 0
    public operator fun plus(other: Duration): Duration = null!!
    public override fun toString(): String = ""
    public fun toDouble(unit: DurationUnit): Double = 0.0
    public fun toLong(unit: DurationUnit): Long = 0L
    public fun toInt(unit: DurationUnit): Int = 0

    public companion object {
        public val ZERO: Duration get() = Duration(0L)
        public val INFINITE: Duration get() = Duration(0L)

        public val Int.nanoseconds: Duration get() = Duration(0L)
        public val Long.nanoseconds: Duration get() = Duration(0L)
        public val Double.nanoseconds: Duration get() = Duration(0L)
        public val Int.microseconds: Duration get() = Duration(0L)
        public val Long.microseconds: Duration get() = Duration(0L)
        public val Double.microseconds: Duration get() = Duration(0L)
        public val Int.milliseconds: Duration get() = Duration(0L)
        public val Long.milliseconds: Duration get() = Duration(0L)
        public val Double.milliseconds: Duration get() = Duration(0L)
        public val Int.seconds: Duration get() = Duration(0L)
        public val Long.seconds: Duration get() = Duration(0L)
        public val Double.seconds: Duration get() = Duration(0L)
        public val Int.minutes: Duration get() = Duration(0L)
        public val Long.minutes: Duration get() = Duration(0L)
        public val Double.minutes: Duration get() = Duration(0L)
        public val Int.hours: Duration get() = Duration(0L)
        public val Long.hours: Duration get() = Duration(0L)
        public val Double.hours: Duration get() = Duration(0L)
        public val Int.days: Duration get() = Duration(0L)
        public val Long.days: Duration get() = Duration(0L)
        public val Double.days: Duration get() = Duration(0L)
    }
}

public fun Int.toDuration(unit: DurationUnit): Duration = null!!
public fun Long.toDuration(unit: DurationUnit): Duration = null!!
public fun Double.toDuration(unit: DurationUnit): Duration = null!!
