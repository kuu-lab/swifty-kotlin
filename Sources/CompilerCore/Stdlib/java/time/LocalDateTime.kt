package java.time

import java.util.Calendar

/** A date-time without a time-zone in the ISO-8601 calendar system. */
public class LocalDateTime private constructor(
    public val date: LocalDate,
    public val time: LocalTime,
) : Comparable<LocalDateTime> {
    public val year: Int
        get() = date.year

    public val monthValue: Int
        get() = date.monthValue

    public val dayOfMonth: Int
        get() = date.dayOfMonth

    public val hour: Int
        get() = time.hour

    public val minute: Int
        get() = time.minute

    public val second: Int
        get() = time.second

    public val nano: Int
        get() = time.nano

    public fun getYear(): Int = year

    public fun getMonthValue(): Int = monthValue

    public fun getMonth(): Month = date.month

    public fun getDayOfMonth(): Int = dayOfMonth

    public fun getDayOfYear(): Int = date.dayOfYear

    public fun getDayOfWeek(): DayOfWeek = date.dayOfWeek

    public fun getHour(): Int = hour

    public fun getMinute(): Int = minute

    public fun getSecond(): Int = second

    public fun getNano(): Int = nano

    public fun toLocalDate(): LocalDate = date

    public fun toLocalTime(): LocalTime = time

    public fun plusYears(years: Long): LocalDateTime = of(date.plusYears(years), time)

    public fun plusMonths(months: Long): LocalDateTime = of(date.plusMonths(months), time)

    public fun plusWeeks(weeks: Long): LocalDateTime = of(date.plusWeeks(weeks), time)

    public fun plusDays(days: Long): LocalDateTime = of(date.plusDays(days), time)

    public fun plusHours(hours: Long): LocalDateTime {
        val days = javaTimeFloorDiv(hours, 24L)
        val hoursWithinDay = javaTimeFloorMod(hours, 24L)
        return of(date.plusDays(days), time.plusHours(hoursWithinDay))
    }

    public fun plusMinutes(minutes: Long): LocalDateTime {
        val days = javaTimeFloorDiv(minutes, 1_440L)
        val minutesWithinDay = javaTimeFloorMod(minutes, 1_440L)
        return of(date.plusDays(days), time.plusMinutes(minutesWithinDay))
    }

    public fun plusSeconds(seconds: Long): LocalDateTime {
        val days = javaTimeFloorDiv(seconds, javaTimeSecondsPerDay)
        val secondsWithinDay = javaTimeFloorMod(seconds, javaTimeSecondsPerDay)
        return of(date.plusDays(days), time.plusSeconds(secondsWithinDay))
    }

    public fun plusNanos(nanos: Long): LocalDateTime {
        val days = javaTimeFloorDiv(nanos, javaTimeNanosPerDay)
        val remainder = javaTimeFloorMod(nanos, javaTimeNanosPerDay)
        val total = time.nanoOfDay + remainder
        val additionalDay = total / javaTimeNanosPerDay
        val nanoOfDay = total % javaTimeNanosPerDay
        return of(date.plusDays(days + additionalDay), LocalTime.ofNanoOfDay(nanoOfDay))
    }

    public fun plus(period: Period): LocalDateTime = of(date.plus(period), time)

    public fun plus(duration: Duration): LocalDateTime =
        plusSeconds(duration.seconds).plusNanos(duration.nano.toLong())

    public fun minus(period: Period): LocalDateTime = of(date.minus(period), time)

    public fun minus(duration: Duration): LocalDateTime =
        minusSeconds(duration.seconds).minusNanos(duration.nano.toLong())

    public fun minusYears(years: Long): LocalDateTime = plusYears(-years)

    public fun minusMonths(months: Long): LocalDateTime = plusMonths(-months)

    public fun minusWeeks(weeks: Long): LocalDateTime = plusWeeks(-weeks)

    public fun minusDays(days: Long): LocalDateTime = plusDays(-days)

    public fun minusHours(hours: Long): LocalDateTime = plusHours(-hours)

    public fun minusMinutes(minutes: Long): LocalDateTime = plusMinutes(-minutes)

    public fun minusSeconds(seconds: Long): LocalDateTime = plusSeconds(-seconds)

    public fun minusNanos(nanos: Long): LocalDateTime = plusNanos(-nanos)

    public fun isBefore(other: LocalDateTime): Boolean = compareTo(other) < 0

    public fun isAfter(other: LocalDateTime): Boolean = compareTo(other) > 0

    public fun format(formatter: java.time.format.DateTimeFormatter): String = formatter.format(this)

    override fun compareTo(other: LocalDateTime): Int {
        val dateComparison = date.compareTo(other.date)
        return if (dateComparison != 0) dateComparison else time.compareTo(other.time)
    }

    override fun equals(other: Any?): Boolean = other is LocalDateTime && date == other.date && time == other.time

    override fun hashCode(): Int = date.hashCode() xor time.hashCode()

    override fun toString(): String = date.toString() + "T" + time.toString()

    public companion object {
        public fun now(): LocalDateTime {
            val calendar = Calendar.getInstance()
            return of(
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH) + 1,
                calendar.get(Calendar.DAY_OF_MONTH),
                calendar.get(Calendar.HOUR_OF_DAY),
                calendar.get(Calendar.MINUTE),
                calendar.get(Calendar.SECOND),
                calendar.get(Calendar.MILLISECOND) * 1_000_000
            )
        }

        public fun of(year: Int, month: Int, dayOfMonth: Int, hour: Int, minute: Int): LocalDateTime =
            of(LocalDate.of(year, month, dayOfMonth), LocalTime.of(hour, minute))

        public fun of(
            year: Int,
            month: Int,
            dayOfMonth: Int,
            hour: Int,
            minute: Int,
            second: Int,
        ): LocalDateTime = of(LocalDate.of(year, month, dayOfMonth), LocalTime.of(hour, minute, second))

        public fun of(
            year: Int,
            month: Int,
            dayOfMonth: Int,
            hour: Int,
            minute: Int,
            second: Int,
            nanoOfSecond: Int,
        ): LocalDateTime = of(
            LocalDate.of(year, month, dayOfMonth),
            LocalTime.of(hour, minute, second, nanoOfSecond)
        )

        public fun of(date: LocalDate, time: LocalTime): LocalDateTime = LocalDateTime(date, time)

        public fun of(date: LocalDate, hour: Int, minute: Int): LocalDateTime =
            of(date, LocalTime.of(hour, minute))

        public fun parse(text: CharSequence): LocalDateTime {
            val value = text.toString()
            val separator = value.indexOf('T')
            if (separator < 0) throw DateTimeException("Invalid ISO date-time: " + value)
            return of(LocalDate.parse(value.substring(0, separator)), LocalTime.parse(value.substring(separator + 1)))
        }
    }
}
