package java.time

import java.time.format.DateTimeFormatter

/** A date-time with a time-zone in the ISO-8601 calendar system. */
public class ZonedDateTime private constructor(
    private val dateTime: LocalDateTime,
    public val offset: ZoneOffset,
    public val zone: ZoneId,
) : Comparable<ZonedDateTime> {
    public val year: Int get() = dateTime.year
    public val monthValue: Int get() = dateTime.monthValue
    public val dayOfMonth: Int get() = dateTime.dayOfMonth
    public val hour: Int get() = dateTime.hour
    public val minute: Int get() = dateTime.minute
    public val second: Int get() = dateTime.second
    public val nano: Int get() = dateTime.nano

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
    public fun getOffset(): ZoneOffset = offset
    public fun getZone(): ZoneId = zone

    public fun toLocalDateTime(): LocalDateTime = dateTime
    public fun toLocalDate(): LocalDate = dateTime.date
    public fun toLocalTime(): LocalTime = dateTime.time
    public fun toOffsetDateTime(): OffsetDateTime = OffsetDateTime.of(dateTime, offset)
    public fun toInstant(): Instant = toOffsetDateTime().toInstant()
    public fun toEpochSecond(): Long = toOffsetDateTime().toEpochSecond()

    public fun withZoneSameInstant(zone: ZoneId): ZonedDateTime = ofInstant(toInstant(), zone)

    public fun withZoneSameLocal(zone: ZoneId): ZonedDateTime = of(dateTime, zone)

    public fun withFixedOffsetZone(): ZonedDateTime = of(dateTime, offset)

    public fun plusYears(years: Long): ZonedDateTime = of(dateTime.plusYears(years), zone)
    public fun plusMonths(months: Long): ZonedDateTime = of(dateTime.plusMonths(months), zone)
    public fun plusWeeks(weeks: Long): ZonedDateTime = of(dateTime.plusWeeks(weeks), zone)
    public fun plusDays(days: Long): ZonedDateTime = of(dateTime.plusDays(days), zone)
    public fun plusHours(hours: Long): ZonedDateTime = ofInstant(toInstant().plusSeconds(hours * 3_600L), zone)
    public fun plusMinutes(minutes: Long): ZonedDateTime = ofInstant(toInstant().plusSeconds(minutes * 60L), zone)
    public fun plusSeconds(seconds: Long): ZonedDateTime = ofInstant(toInstant().plusSeconds(seconds), zone)
    public fun plusNanos(nanos: Long): ZonedDateTime = ofInstant(toInstant().plusNanos(nanos), zone)
    public fun plus(period: Period): ZonedDateTime = of(dateTime.plus(period), zone)
    public fun plus(duration: Duration): ZonedDateTime = ofInstant(toInstant().plus(duration), zone)

    public fun minusYears(years: Long): ZonedDateTime = plusYears(-years)
    public fun minusMonths(months: Long): ZonedDateTime = plusMonths(-months)
    public fun minusWeeks(weeks: Long): ZonedDateTime = plusWeeks(-weeks)
    public fun minusDays(days: Long): ZonedDateTime = plusDays(-days)
    public fun minusHours(hours: Long): ZonedDateTime = plusHours(-hours)
    public fun minusMinutes(minutes: Long): ZonedDateTime = plusMinutes(-minutes)
    public fun minusSeconds(seconds: Long): ZonedDateTime = plusSeconds(-seconds)
    public fun minusNanos(nanos: Long): ZonedDateTime = plusNanos(-nanos)
    public fun minus(period: Period): ZonedDateTime = of(dateTime.minus(period), zone)
    public fun minus(duration: Duration): ZonedDateTime = ofInstant(toInstant().minus(duration), zone)

    public fun format(formatter: DateTimeFormatter): String = formatter.format(this)

    public fun isBefore(other: ZonedDateTime): Boolean = toInstant().compareTo(other.toInstant()) < 0
    public fun isAfter(other: ZonedDateTime): Boolean = toInstant().compareTo(other.toInstant()) > 0
    public fun isEqual(other: ZonedDateTime): Boolean = toInstant() == other.toInstant()

    override fun compareTo(other: ZonedDateTime): Int {
        val instantComparison = toInstant().compareTo(other.toInstant())
        if (instantComparison != 0) return instantComparison
        val localComparison = dateTime.compareTo(other.dateTime)
        if (localComparison != 0) return localComparison
        val offsetComparison = offset.compareTo(other.offset)
        if (offsetComparison != 0) return offsetComparison
        return zone.id.compareTo(other.zone.id)
    }

    override fun equals(other: Any?): Boolean =
        other is ZonedDateTime && dateTime == other.dateTime && offset == other.offset && zone == other.zone

    override fun hashCode(): Int = dateTime.hashCode() xor offset.hashCode() xor zone.hashCode()

    override fun toString(): String = dateTime.toString() + offset.toString() +
        if (zone.id != offset.id) "[" + zone.id + "]" else ""

    public companion object {
        public val MIN: ZonedDateTime = of(LocalDateTime.of(-999_999_999, 1, 1, 0, 0), ZoneOffset.MAX)
        public val MAX: ZonedDateTime = of(LocalDateTime.of(999_999_999, 12, 31, 23, 59, 59, 999_999_999), ZoneOffset.MIN)

        public fun now(): ZonedDateTime = now(ZoneId.systemDefault())

        public fun now(zone: ZoneId): ZonedDateTime = ofInstant(Instant.now(), zone)

        public fun of(date: LocalDate, time: LocalTime, zone: ZoneId): ZonedDateTime =
            of(LocalDateTime.of(date, time), zone)

        public fun of(dateTime: LocalDateTime, zone: ZoneId): ZonedDateTime =
            ZonedDateTime(dateTime, javaTimeZoneOffsetForLocal(dateTime, zone), zone)

        public fun of(
            year: Int,
            month: Int,
            dayOfMonth: Int,
            hour: Int,
            minute: Int,
            zone: ZoneId,
        ): ZonedDateTime = of(LocalDateTime.of(year, month, dayOfMonth, hour, minute), zone)

        public fun of(
            year: Int,
            month: Int,
            dayOfMonth: Int,
            hour: Int,
            minute: Int,
            second: Int,
            nanoOfSecond: Int,
            zone: ZoneId,
        ): ZonedDateTime = of(LocalDateTime.of(year, month, dayOfMonth, hour, minute, second, nanoOfSecond), zone)

        public fun ofInstant(instant: Instant, zone: ZoneId): ZonedDateTime {
            val offset = zone.javaTimeOffsetAt(instant.epochSecond)
            val local = OffsetDateTime.ofInstant(instant, offset)
            return ZonedDateTime(local.toLocalDateTime(), offset, zone)
        }

        public fun parse(text: CharSequence): ZonedDateTime {
            val value = text.toString()
            val bracket = value.indexOf('[')
            val zone = if (bracket >= 0 && value.endsWith("]")) {
                ZoneId.of(value.substring(bracket + 1, value.length - 1))
            } else {
                null
            }
            val offsetDateTime = OffsetDateTime.parse(if (bracket >= 0) value.substring(0, bracket) else value)
            return if (zone == null) of(offsetDateTime.toLocalDateTime(), offsetDateTime.offset)
            else ofInstant(offsetDateTime.toInstant(), zone)
        }
    }
}

private fun javaTimeZoneOffsetForLocal(dateTime: LocalDateTime, zone: ZoneId): ZoneOffset {
    val localEpochSecond = dateTime.date.toEpochDay() * javaTimeSecondsPerDay + dateTime.time.secondOfDay
    return zone.javaTimeOffsetAt(localEpochSecond)
}
