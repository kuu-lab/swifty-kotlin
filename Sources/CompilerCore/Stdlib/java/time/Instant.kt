package java.time

import kotlin.time.Instant as KotlinInstant
import java.util.Calendar

/** An instantaneous point on the time-line measured from the Unix epoch. */
public class Instant private constructor(
    public val epochSecond: Long,
    public val nano: Int,
) : Comparable<Instant> {
    public fun getEpochSecond(): Long = epochSecond

    public fun getNano(): Int = nano

    public fun toEpochMilli(): Long {
        val secondsInMillis = epochSecond * 1_000L
        return secondsInMillis + nano / 1_000_000
    }

    public fun plusSeconds(secondsToAdd: Long): Instant = ofEpochSecond(epochSecond + secondsToAdd, nano.toLong())

    public fun plusMillis(millisToAdd: Long): Instant = plus(Duration.ofMillis(millisToAdd))

    public fun plusNanos(nanosToAdd: Long): Instant = ofEpochSecond(epochSecond, nano.toLong() + nanosToAdd)

    public fun plus(duration: Duration): Instant = ofEpochSecond(epochSecond + duration.seconds, nano.toLong() + duration.nano)

    public fun minusSeconds(secondsToSubtract: Long): Instant = plusSeconds(-secondsToSubtract)

    public fun minusMillis(millisToSubtract: Long): Instant = plusMillis(-millisToSubtract)

    public fun minusNanos(nanosToSubtract: Long): Instant = plusNanos(-nanosToSubtract)

    public fun minus(duration: Duration): Instant = ofEpochSecond(epochSecond - duration.seconds, nano.toLong() - duration.nano)

    public fun isBefore(other: Instant): Boolean = compareTo(other) < 0

    public fun isAfter(other: Instant): Boolean = compareTo(other) > 0

    override fun compareTo(other: Instant): Int {
        if (epochSecond != other.epochSecond) return epochSecond.compareTo(other.epochSecond)
        return nano.compareTo(other.nano)
    }

    override fun equals(other: Any?): Boolean = other is Instant && epochSecond == other.epochSecond && nano == other.nano

    override fun hashCode(): Int = epochSecond.hashCode() xor nano.hashCode()

    override fun toString(): String = KotlinInstant.fromEpochSeconds(epochSecond, nano.toLong()).toString()

    public companion object {
        public val EPOCH: Instant = Instant(0L, 0)
        public val MIN: Instant = Instant(-31_557_014_167_219_200L, 0)
        public val MAX: Instant = Instant(31_556_889_864_403_199L, 999_999_999)

        public fun now(): Instant {
            return ofEpochMilli(Calendar.getInstance().getTimeInMillis())
        }

        public fun ofEpochMilli(epochMilli: Long): Instant {
            val seconds = javaTimeFloorDiv(epochMilli, 1_000L)
            val millis = javaTimeFloorMod(epochMilli, 1_000L)
            return Instant(seconds, (millis * 1_000_000L).toInt())
        }

        public fun ofEpochSecond(epochSecond: Long): Instant = ofEpochSecond(epochSecond, 0L)

        public fun ofEpochSecond(epochSecond: Long, nanoAdjustment: Long): Instant {
            val normalizedSeconds = epochSecond + javaTimeFloorDiv(nanoAdjustment, javaTimeNanosPerSecond)
            val normalizedNano = javaTimeFloorMod(nanoAdjustment, javaTimeNanosPerSecond).toInt()
            return Instant(normalizedSeconds, normalizedNano)
        }

        public fun parse(text: CharSequence): Instant {
            val value = text.toString()
            val separator = value.indexOf('T')
            if (separator < 0) throw DateTimeException("Invalid ISO instant: " + value)

            val zoneIndex = value.indexOf('Z', separator)
            val offsetIndex = if (zoneIndex >= 0) zoneIndex else {
                val plusIndex = value.indexOf('+', separator)
                val minusIndex = value.indexOf('-', separator)
                if (plusIndex >= 0) plusIndex else minusIndex
            }
            if (offsetIndex < 0) throw DateTimeException("Invalid ISO instant: " + value)

            val dateTime = LocalDateTime.parse(value.substring(0, offsetIndex))
            val offsetSeconds = if (value[offsetIndex] == 'Z') {
                0
            } else {
                parseInstantOffsetSeconds(value.substring(offsetIndex))
            }
            val epochSecond = dateTime.date.toEpochDay() * javaTimeSecondsPerDay +
                dateTime.time.secondOfDay - offsetSeconds
            return ofEpochSecond(epochSecond, dateTime.nano.toLong())
        }
    }
}

private fun parseInstantOffsetSeconds(offset: String): Long {
    if (offset.length != 6 || (offset[0] != '+' && offset[0] != '-') || offset[3] != ':') {
        throw DateTimeException("Invalid ISO offset: " + offset)
    }
    try {
        val hours = offset.substring(1, 3).toInt()
        val minutes = offset.substring(4, 6).toInt()
        if (hours > 18 || minutes > 59 || (hours == 18 && minutes != 0)) {
            throw DateTimeException("Invalid ISO offset: " + offset)
        }
        val total = (hours * 3_600 + minutes * 60).toLong()
        return if (offset[0] == '-') -total else total
    } catch (error: NumberFormatException) {
        throw DateTimeException("Invalid ISO offset: " + offset)
    }
}
