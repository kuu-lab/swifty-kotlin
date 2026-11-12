package kotlin.time

@JvmInline
public value class Duration private constructor(private val rawValue: Long) : Comparable<Duration> {
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
    public override fun toString(): String = ""
    public fun toDouble(unit: DurationUnit): Double = 0.0
    public fun toLong(unit: DurationUnit): Long = 0L
    public fun toInt(unit: DurationUnit): Int = 0

    public companion object {
        public val ZERO: Duration get() = Duration(0L)
        public val INFINITE: Duration get() = Duration(0L)
    }
}

public fun Int.toDuration(unit: DurationUnit): Duration = null!!
public fun Long.toDuration(unit: DurationUnit): Duration = null!!
public fun Double.toDuration(unit: DurationUnit): Duration = null!!
