package kotlin.time

import java.time.Instant as JavaInstant
import kotlin.time.jdk8.toKotlinInstant

public class Instant internal constructor(
    public val epochSeconds: Long,
    public val nanosecondsOfSecond: Int,
) : Comparable<Instant>, java.io.Serializable {
    public fun toEpochMilliseconds(): Long = instantEpochMilliseconds(this)

    public operator fun plus(duration: Duration): Instant {
        if (duration.isInfinite()) return if (duration.isNegative()) MIN else MAX
        val seconds = duration.inWholeSeconds
        val fraction = duration + seconds.toDuration(DurationUnit.SECONDS).negated()
        return fromEpochSeconds(epochSeconds + seconds, nanosecondsOfSecond.toLong() + fraction.inWholeNanoseconds)
    }

    public operator fun minus(duration: Duration): Instant = plus(duration.negated())

    public operator fun minus(other: Instant): Duration =
        (epochSeconds - other.epochSeconds).toDuration(DurationUnit.SECONDS) +
            (nanosecondsOfSecond - other.nanosecondsOfSecond).toDuration(DurationUnit.NANOSECONDS)

    public override fun compareTo(other: Instant): Int {
        val secondsOrder = epochSeconds.compareTo(other.epochSeconds)
        if (secondsOrder != 0) return secondsOrder
        return nanosecondsOfSecond.compareTo(other.nanosecondsOfSecond)
    }

    public override fun equals(other: Any?): Boolean =
        other is Instant && epochSeconds == other.epochSeconds && nanosecondsOfSecond == other.nanosecondsOfSecond

    public override fun hashCode(): Int = epochSeconds.hashCode() + 51 * nanosecondsOfSecond

    public override fun toString(): String = instantFormatIso(this)

    public companion object {
        internal val MIN: Instant get() = Instant(INSTANT_MIN_SECOND, 0)
        internal val MAX: Instant get() = Instant(INSTANT_MAX_SECOND, 999_999_999)

        public val DISTANT_PAST: Instant get() = Instant(INSTANT_DISTANT_PAST_SECONDS, 999_999_999)
        public val DISTANT_FUTURE: Instant get() = Instant(INSTANT_DISTANT_FUTURE_SECONDS, 0)

        internal fun now(): Instant = JavaInstant.now().toKotlinInstant()

        public fun fromEpochMilliseconds(epochMilliseconds: Long): Instant =
            fromEpochSeconds(epochMilliseconds / 1_000L, (epochMilliseconds % 1_000L) * 1_000_000L)

        public fun fromEpochSeconds(epochSeconds: Long, nanosecondAdjustment: Long = 0L): Instant {
            var secondsAdjustment = nanosecondAdjustment / 1_000_000_000L
            var nanos = nanosecondAdjustment % 1_000_000_000L
            if (nanos < 0L) {
                secondsAdjustment--
                nanos += 1_000_000_000L
            }
            if (secondsAdjustment > 0L && epochSeconds > Long.MAX_VALUE - secondsAdjustment) return MAX
            if (secondsAdjustment < 0L && epochSeconds < Long.MIN_VALUE - secondsAdjustment) return MIN
            val seconds = epochSeconds + secondsAdjustment
            if (seconds < INSTANT_MIN_SECOND) return MIN
            if (seconds > INSTANT_MAX_SECOND) return MAX
            return Instant(seconds, nanos.toInt())
        }

        public fun fromEpochSeconds(epochSeconds: Long, nanosecondAdjustment: Int): Instant =
            fromEpochSeconds(epochSeconds, nanosecondAdjustment.toLong())

        public fun parse(input: CharSequence): Instant =
            parseOrNull(input) ?: throw IllegalArgumentException("Invalid instant string: $input")

        public fun parseOrNull(input: CharSequence): Instant? = instantParseOrNull(input.toString())
    }
}
