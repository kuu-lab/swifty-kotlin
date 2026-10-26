package java.time

/** A time-based amount of time stored as seconds and nanoseconds. */
public class Duration private constructor(
    public val seconds: Long,
    public val nano: Int,
) : Comparable<Duration> {
    public fun getSeconds(): Long = seconds

    public fun getNano(): Int = nano

    public fun isZero(): Boolean = seconds == 0L && nano == 0

    public fun isNegative(): Boolean = seconds < 0L

    public fun plus(other: Duration): Duration = ofSeconds(seconds + other.seconds, nano.toLong() + other.nano)

    public fun minus(other: Duration): Duration = ofSeconds(seconds - other.seconds, nano.toLong() - other.nano)

    public fun plusSeconds(secondsToAdd: Long): Duration = ofSeconds(seconds + secondsToAdd, nano.toLong())

    public fun plusMillis(millisToAdd: Long): Duration = plus(ofMillis(millisToAdd))

    public fun plusNanos(nanosToAdd: Long): Duration = ofSeconds(seconds, nano.toLong() + nanosToAdd)

    public fun minusSeconds(secondsToSubtract: Long): Duration = plusSeconds(-secondsToSubtract)

    public fun minusMillis(millisToSubtract: Long): Duration = plusMillis(-millisToSubtract)

    public fun minusNanos(nanosToSubtract: Long): Duration = plusNanos(-nanosToSubtract)

    public fun multipliedBy(multiplicand: Long): Duration {
        if (isZero() || multiplicand == 0L) return ZERO
        if (multiplicand == 1L) return this
        val secondsProduct = durationMultiplyExact(seconds, multiplicand)
        val nanosProduct = durationMultiplyExact(nano.toLong(), multiplicand)
        return ofSeconds(secondsProduct, nanosProduct)
    }

    public fun negated(): Duration = ofSeconds(-seconds, -nano.toLong())

    public fun toDays(): Long = seconds / javaTimeSecondsPerDay

    public fun toHours(): Long = seconds / 3_600L

    public fun toMinutes(): Long = seconds / 60L

    public fun toMillis(): Long = seconds * 1_000L + nano / 1_000_000

    public fun toNanos(): Long = seconds * javaTimeNanosPerSecond + nano

    public fun toSeconds(): Long = seconds

    override fun compareTo(other: Duration): Int {
        if (seconds != other.seconds) return seconds.compareTo(other.seconds)
        return nano.compareTo(other.nano)
    }

    override fun equals(other: Any?): Boolean = other is Duration && seconds == other.seconds && nano == other.nano

    override fun hashCode(): Int = seconds.hashCode() xor nano.hashCode()

    override fun toString(): String {
        val negative = seconds < 0L
        val absoluteSeconds: Long
        val absoluteNano: Int
        if (negative && nano > 0) {
            absoluteSeconds = -(seconds + 1L)
            absoluteNano = 1_000_000_000 - nano
        } else {
            absoluteSeconds = if (negative) -seconds else seconds
            absoluteNano = nano
        }
        val hours = absoluteSeconds / 3_600L
        val minutes = absoluteSeconds % 3_600L / 60L
        val secondPart = absoluteSeconds % 60L
        val sign = if (negative) "-" else ""
        val builder = StringBuilder("PT")
        if (hours != 0L) builder.append(sign).append(hours).append('H')
        if (minutes != 0L) builder.append(sign).append(minutes).append('M')
        if (secondPart != 0L || absoluteNano != 0 || (hours == 0L && minutes == 0L)) {
            builder.append(sign).append(secondPart)
            if (absoluteNano != 0) {
                val fraction = (absoluteNano + 1_000_000_000).toString().substring(1)
                var end = fraction.length
                while (end > 0 && fraction[end - 1] == '0') end -= 1
                builder.append('.').append(fraction.substring(0, end))
            }
            builder.append('S')
        }
        return builder.toString()
    }

    public companion object {
        public val ZERO: Duration = Duration(0L, 0)

        public fun ofDays(days: Long): Duration = ofSeconds(days * javaTimeSecondsPerDay)

        public fun ofHours(hours: Long): Duration = ofSeconds(hours * 3_600L)

        public fun ofMinutes(minutes: Long): Duration = ofSeconds(minutes * 60L)

        public fun ofSeconds(seconds: Long): Duration = if (seconds == 0L) ZERO else Duration(seconds, 0)

        public fun ofSeconds(seconds: Long, nanoAdjustment: Long): Duration {
            val normalizedSeconds = seconds + javaTimeFloorDiv(nanoAdjustment, javaTimeNanosPerSecond)
            val normalizedNano = javaTimeFloorMod(nanoAdjustment, javaTimeNanosPerSecond).toInt()
            return if (normalizedSeconds == 0L && normalizedNano == 0) ZERO else Duration(normalizedSeconds, normalizedNano)
        }

        public fun ofMillis(milliseconds: Long): Duration {
            val seconds = milliseconds / 1_000L
            val remainder = milliseconds % 1_000L
            return ofSeconds(seconds, remainder * 1_000_000L)
        }

        public fun ofNanos(nanoseconds: Long): Duration =
            ofSeconds(javaTimeFloorDiv(nanoseconds, javaTimeNanosPerSecond), javaTimeFloorMod(nanoseconds, javaTimeNanosPerSecond))

        public fun between(startInclusive: Instant, endExclusive: Instant): Duration =
            ofSeconds(
                endExclusive.epochSecond - startInclusive.epochSecond,
                endExclusive.nano.toLong() - startInclusive.nano
            )

        public fun between(startInclusive: LocalDateTime, endExclusive: LocalDateTime): Duration {
            val days = endExclusive.date.toEpochDay() - startInclusive.date.toEpochDay()
            val seconds = days * javaTimeSecondsPerDay +
                endExclusive.time.secondOfDay - startInclusive.time.secondOfDay
            return ofSeconds(seconds, endExclusive.nano.toLong() - startInclusive.nano)
        }

        public fun between(startInclusive: LocalTime, endExclusive: LocalTime): Duration =
            ofSeconds(
                endExclusive.secondOfDay.toLong() - startInclusive.secondOfDay,
                endExclusive.nano.toLong() - startInclusive.nano
            )
    }
}

private fun durationMultiplyExact(left: Long, right: Long): Long {
    if (left == 0L || right == 0L) return 0L
    val minValue = -9_223_372_036_854_775_807L - 1L
    if ((left == minValue && right == -1L) || (right == minValue && left == -1L)) {
        throw ArithmeticException("long overflow")
    }
    val product = left * right
    if (product / right != left) throw ArithmeticException("long overflow")
    return product
}
