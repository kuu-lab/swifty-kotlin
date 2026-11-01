package java.time

import java.time.format.DateTimeFormatter
import java.util.Comparator

/**
 * A date-time with an offset from UTC/Greenwich in the ISO-8601 calendar system,
 * such as {@code 2007-12-03T10:15:30+01:00}.
 */
public class OffsetDateTime private constructor(
    private val dateTime: LocalDateTime,
    public val offset: ZoneOffset,
) : Comparable<OffsetDateTime> {
    public val year: Int
        get() = dateTime.year

    public val monthValue: Int
        get() = dateTime.monthValue

    public val dayOfMonth: Int
        get() = dateTime.dayOfMonth

    public val hour: Int
        get() = dateTime.hour

    public val minute: Int
        get() = dateTime.minute

    public val second: Int
        get() = dateTime.second

    public val nano: Int
        get() = dateTime.nano

    public fun getOffset(): ZoneOffset = offset

    public fun getYear(): Int = year

    public fun getMonthValue(): Int = monthValue

    public fun getMonth(): Month = dateTime.getMonth()

    public fun getDayOfMonth(): Int = dayOfMonth

    public fun getDayOfYear(): Int = dateTime.getDayOfYear()

    public fun getDayOfWeek(): DayOfWeek = dateTime.getDayOfWeek()

    public fun getHour(): Int = hour

    public fun getMinute(): Int = minute

    public fun getSecond(): Int = second

    public fun getNano(): Int = nano

    public fun toLocalDateTime(): LocalDateTime = dateTime

    public fun toLocalDate(): LocalDate = dateTime.date

    public fun toLocalTime(): LocalTime = dateTime.time

    /** Converts this date-time to the number of seconds from the epoch of 1970-01-01T00:00:00Z. */
    public fun toEpochSecond(): Long =
        dateTime.date.toEpochDay() * javaTimeSecondsPerDay + dateTime.time.secondOfDay - offset.totalSeconds

    /** Converts this date-time to an [Instant]. */
    public fun toInstant(): Instant = Instant.ofEpochSecond(toEpochSecond(), nano.toLong())

    /**
     * Returns a copy of this [OffsetDateTime] with the specified offset, keeping
     * the same local date-time.
     */
    public fun withOffsetSameLocal(newOffset: ZoneOffset): OffsetDateTime = OffsetDateTime(dateTime, newOffset)

    /**
     * Returns a copy of this [OffsetDateTime] with the specified offset, adjusting
     * the local date-time so the result represents the same instant.
     */
    public fun withOffsetSameInstant(newOffset: ZoneOffset): OffsetDateTime {
        if (newOffset == offset) {
            return this
        }
        val difference = newOffset.totalSeconds - offset.totalSeconds
        return OffsetDateTime(dateTime.plusSeconds(difference.toLong()), newOffset)
    }

    public fun plusYears(years: Long): OffsetDateTime = OffsetDateTime(dateTime.plusYears(years), offset)

    public fun plusMonths(months: Long): OffsetDateTime = OffsetDateTime(dateTime.plusMonths(months), offset)

    public fun plusWeeks(weeks: Long): OffsetDateTime = OffsetDateTime(dateTime.plusWeeks(weeks), offset)

    public fun plusDays(days: Long): OffsetDateTime = OffsetDateTime(dateTime.plusDays(days), offset)

    public fun plusHours(hours: Long): OffsetDateTime = OffsetDateTime(dateTime.plusHours(hours), offset)

    public fun plusMinutes(minutes: Long): OffsetDateTime = OffsetDateTime(dateTime.plusMinutes(minutes), offset)

    public fun plusSeconds(seconds: Long): OffsetDateTime = OffsetDateTime(dateTime.plusSeconds(seconds), offset)

    public fun plusNanos(nanos: Long): OffsetDateTime = OffsetDateTime(dateTime.plusNanos(nanos), offset)

    public fun plus(period: Period): OffsetDateTime = OffsetDateTime(dateTime.plus(period), offset)

    public fun plus(duration: Duration): OffsetDateTime = OffsetDateTime(dateTime.plus(duration), offset)

    public fun minusYears(years: Long): OffsetDateTime = plusYears(-years)

    public fun minusMonths(months: Long): OffsetDateTime = plusMonths(-months)

    public fun minusWeeks(weeks: Long): OffsetDateTime = plusWeeks(-weeks)

    public fun minusDays(days: Long): OffsetDateTime = plusDays(-days)

    public fun minusHours(hours: Long): OffsetDateTime = plusHours(-hours)

    public fun minusMinutes(minutes: Long): OffsetDateTime = plusMinutes(-minutes)

    public fun minusSeconds(seconds: Long): OffsetDateTime = plusSeconds(-seconds)

    public fun minusNanos(nanos: Long): OffsetDateTime = plusNanos(-nanos)

    public fun minus(period: Period): OffsetDateTime = OffsetDateTime(dateTime.minus(period), offset)

    public fun minus(duration: Duration): OffsetDateTime = OffsetDateTime(dateTime.minus(duration), offset)

    public fun format(formatter: DateTimeFormatter): String = formatter.format(this)

    /**
     * Checks if the instant of this date-time is after that of the specified
     * date-time, comparing only the instant on the time-line.
     */
    public fun isAfter(other: OffsetDateTime): Boolean =
        toEpochSecond() > other.toEpochSecond() ||
            (toEpochSecond() == other.toEpochSecond() && nano > other.nano)

    /**
     * Checks if the instant of this date-time is before that of the specified
     * date-time, comparing only the instant on the time-line.
     */
    public fun isBefore(other: OffsetDateTime): Boolean =
        toEpochSecond() < other.toEpochSecond() ||
            (toEpochSecond() == other.toEpochSecond() && nano < other.nano)

    /**
     * Checks if the instant of this date-time equals that of the specified
     * date-time, comparing only the instant on the time-line.
     */
    public fun isEqual(other: OffsetDateTime): Boolean =
        toEpochSecond() == other.toEpochSecond() && nano == other.nano

    /**
     * Compares this date-time to another by instant on the time-line, falling
     * back to the local date-time for consistency with [equals].
     */
    override fun compareTo(other: OffsetDateTime): Int {
        val instantComparison = javaTimeCompareOffsetInstant(this, other)
        if (instantComparison != 0) {
            return instantComparison
        }
        return dateTime.compareTo(other.dateTime)
    }

    /** The comparison is based on the local date-time and the offset. */
    override fun equals(other: Any?): Boolean =
        other is OffsetDateTime && dateTime == other.dateTime && offset == other.offset

    override fun hashCode(): Int = dateTime.hashCode() xor offset.hashCode()

    override fun toString(): String = dateTime.toString() + offset.toString()

    public companion object {
        /** The minimum supported [OffsetDateTime], {@code -999999999-01-01T00:00+18:00}. */
        public val MIN: OffsetDateTime = of(-999_999_999, 1, 1, 0, 0, 0, 0, ZoneOffset.MAX)

        /** The maximum supported [OffsetDateTime], {@code +999999999-12-31T23:59:59.999999999-18:00}. */
        public val MAX: OffsetDateTime = of(999_999_999, 12, 31, 23, 59, 59, 999_999_999, ZoneOffset.MIN)

        /**
         * Returns a comparator that sorts date-times by instant on the time-line,
         * falling back to the local date-time when the offsets are equal.
         */
        public fun timeLineOrder(): Comparator<OffsetDateTime> = Comparator { first, second ->
            javaTimeCompareOffsetInstant(first, second)
        }

        /** Obtains the current date-time from the system clock in the default time-zone. */
        public fun now(): OffsetDateTime = ofInstant(Instant.now(), ZoneId.systemDefault())

        /** Obtains the current date-time from the system clock in the specified time-zone. */
        public fun now(zone: ZoneId): OffsetDateTime = ofInstant(Instant.now(), zone)

        /** Obtains an instance of [OffsetDateTime] from a date, time and offset. */
        public fun of(date: LocalDate, time: LocalTime, offset: ZoneOffset): OffsetDateTime =
            OffsetDateTime(LocalDateTime.of(date, time), offset)

        /** Obtains an instance of [OffsetDateTime] from a date-time and offset. */
        public fun of(dateTime: LocalDateTime, offset: ZoneOffset): OffsetDateTime =
            OffsetDateTime(dateTime, offset)

        /** Obtains an instance of [OffsetDateTime] from the seven fields and an offset. */
        public fun of(
            year: Int,
            month: Int,
            dayOfMonth: Int,
            hour: Int,
            minute: Int,
            second: Int,
            nanoOfSecond: Int,
            offset: ZoneOffset,
        ): OffsetDateTime = OffsetDateTime(
            LocalDateTime.of(year, month, dayOfMonth, hour, minute, second, nanoOfSecond),
            offset
        )

        /** Obtains an instance of [OffsetDateTime] from an [Instant] and zone ID. */
        public fun ofInstant(instant: Instant, zone: ZoneId): OffsetDateTime {
            val offset = zone.javaTimeOffsetAt(instant.epochSecond)
            val epochSecond = instant.epochSecond + offset.totalSeconds
            val epochDay = javaTimeFloorDiv(epochSecond, javaTimeSecondsPerDay)
            val secondOfDay = javaTimeFloorMod(epochSecond, javaTimeSecondsPerDay)
            val date = LocalDate.ofEpochDay(epochDay)
            val time = LocalTime.ofNanoOfDay(secondOfDay * javaTimeNanosPerSecond + instant.nano)
            return OffsetDateTime(LocalDateTime.of(date, time), offset)
        }

        /**
         * Obtains an instance of [OffsetDateTime] from a text string such as
         * {@code 2007-12-03T10:15:30+01:00} or {@code 2007-12-03T10:15:30Z}.
         */
        public fun parse(text: CharSequence): OffsetDateTime {
            val value = text.toString()
            val separator = value.indexOf('T')
            if (separator < 0) throw DateTimeException("Invalid ISO offset date-time: " + value)
            var offsetIndex = -1
            var index = separator + 1
            while (index < value.length) {
                val current = value[index]
                if (current == '+' || current == '-' || current == 'Z') {
                    offsetIndex = index
                    break
                }
                index += 1
            }
            if (offsetIndex < 0) throw DateTimeException("Invalid ISO offset date-time: " + value)
            val dateTime = LocalDateTime.parse(value.substring(0, offsetIndex))
            return OffsetDateTime(dateTime, ZoneOffset.of(value.substring(offsetIndex)))
        }
    }
}

private fun javaTimeCompareOffsetInstant(first: OffsetDateTime, second: OffsetDateTime): Int {
    if (first.offset == second.offset) {
        return first.toLocalDateTime().compareTo(second.toLocalDateTime())
    }
    val epochComparison = first.toEpochSecond().compareTo(second.toEpochSecond())
    if (epochComparison != 0) {
        return epochComparison
    }
    return first.nano.compareTo(second.nano)
}
