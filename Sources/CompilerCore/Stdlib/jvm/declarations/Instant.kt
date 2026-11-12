package kotlin.time

public class Instant internal constructor(
    public val epochSeconds: Long,
    public val nanosecondsOfSecond: Int,
) : Comparable<Instant> {
    public fun toEpochMilliseconds(): Long = 0L
    public operator fun plus(duration: Duration): Instant = this
    public operator fun minus(duration: Duration): Instant = this
    public operator fun minus(other: Instant): Duration = null!!
    public override fun compareTo(other: Instant): Int = 0

    public companion object {
        public val DISTANT_PAST: Instant get() = null!!
        public val DISTANT_FUTURE: Instant get() = null!!

        public fun fromEpochMilliseconds(epochMilliseconds: Long): Instant = null!!
        public fun fromEpochSeconds(epochSeconds: Long, nanosecondAdjustment: Long = 0L): Instant = null!!
        public fun fromEpochSeconds(epochSeconds: Long, nanosecondAdjustment: Int): Instant = null!!
        public fun parse(input: CharSequence): Instant = null!!
        public fun parseOrNull(input: CharSequence): Instant? = null
    }
}
