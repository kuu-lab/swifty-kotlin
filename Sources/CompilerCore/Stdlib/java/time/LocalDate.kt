package java.time

import java.util.Calendar

/** A date without a time-zone in the ISO-8601 calendar system. */
public class LocalDate private constructor(
    public val year: Int,
    public val monthValue: Int,
    public val dayOfMonth: Int,
) : Comparable<LocalDate> {
    public val month: Month
        get() = Month.of(monthValue)

    public val dayOfWeek: DayOfWeek
        get() = DayOfWeek.of(javaTimeFloorMod(toEpochDay() + 3L, 7L).toInt() + 1)

    public val dayOfYear: Int
        get() = (toEpochDay() - javaTimeDaysFromCivil(year, 1, 1) + 1L).toInt()

    public fun getYear(): Int = year

    public fun getMonthValue(): Int = monthValue

    public fun getMonth(): Month = month

    public fun getDayOfMonth(): Int = dayOfMonth

    public fun getDayOfYear(): Int = dayOfYear

    public fun getDayOfWeek(): DayOfWeek = dayOfWeek

    public fun isLeapYear(): Boolean = javaTimeIsLeapYear(year)

    public fun lengthOfMonth(): Int = javaTimeLengthOfMonth(year, monthValue)

    public fun lengthOfYear(): Int = if (isLeapYear()) 366 else 365

    public fun toEpochDay(): Long = javaTimeDaysFromCivil(year, monthValue, dayOfMonth)

    public fun plusDays(days: Long): LocalDate = ofEpochDay(toEpochDay() + days)

    public fun minusDays(days: Long): LocalDate = plusDays(-days)

    public fun plusWeeks(weeks: Long): LocalDate = plusDays(weeks * 7L)

    public fun minusWeeks(weeks: Long): LocalDate = plusWeeks(-weeks)

    public fun plusMonths(months: Long): LocalDate {
        val monthCount = year.toLong() * 12L + (monthValue - 1L) + months
        val newYear = javaTimeFloorDiv(monthCount, 12L).toInt()
        val newMonth = javaTimeFloorMod(monthCount, 12L).toInt() + 1
        return of(newYear, newMonth, minOf(dayOfMonth, javaTimeLengthOfMonth(newYear, newMonth)))
    }

    public fun minusMonths(months: Long): LocalDate = plusMonths(-months)

    public fun plusYears(years: Long): LocalDate = plusMonths(years * 12L)

    public fun minusYears(years: Long): LocalDate = plusYears(-years)

    public fun plus(period: Period): LocalDate = plusMonths(period.toTotalMonths()).plusDays(period.days.toLong())

    public fun minus(period: Period): LocalDate = minusMonths(period.toTotalMonths()).minusDays(period.days.toLong())

    public fun withYear(newYear: Int): LocalDate =
        of(newYear, monthValue, minOf(dayOfMonth, javaTimeLengthOfMonth(newYear, monthValue)))

    public fun withMonth(newMonth: Int): LocalDate =
        of(year, newMonth, minOf(dayOfMonth, javaTimeLengthOfMonth(year, newMonth)))

    public fun withDayOfMonth(newDay: Int): LocalDate = of(year, monthValue, newDay)

    public fun atStartOfDay(): LocalDateTime = atTime(0, 0)

    public fun atTime(hour: Int, minute: Int): LocalDateTime =
        LocalDateTime.of(this, LocalTime.of(hour, minute))

    public fun atTime(time: LocalTime): LocalDateTime = LocalDateTime.of(this, time)

    public fun isBefore(other: LocalDate): Boolean = compareTo(other) < 0

    public fun isAfter(other: LocalDate): Boolean = compareTo(other) > 0

    public fun format(formatter: java.time.format.DateTimeFormatter): String = formatter.format(this)

    override fun compareTo(other: LocalDate): Int {
        if (year != other.year) return year.compareTo(other.year)
        if (monthValue != other.monthValue) return monthValue.compareTo(other.monthValue)
        return dayOfMonth.compareTo(other.dayOfMonth)
    }

    override fun equals(other: Any?): Boolean =
        other is LocalDate && year == other.year && monthValue == other.monthValue && dayOfMonth == other.dayOfMonth

    override fun hashCode(): Int = year * 37 + monthValue * 13 + dayOfMonth

    override fun toString(): String =
        javaTimeFormatYear(year) + "-" + javaTimeTwoDigits(monthValue) + "-" + javaTimeTwoDigits(dayOfMonth)

    public companion object {
        public fun now(): LocalDate {
            val calendar = Calendar.getInstance()
            return of(calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH) + 1, calendar.get(Calendar.DAY_OF_MONTH))
        }

        public fun of(year: Int, month: Int, dayOfMonth: Int): LocalDate {
            if (year < -999_999_999 || year > 999_999_999) {
                throw DateTimeException("Invalid value for Year: " + year)
            }
            if (month < 1 || month > 12) {
                throw DateTimeException("Invalid value for MonthOfYear: " + month)
            }
            val length = javaTimeLengthOfMonth(year, month)
            if (dayOfMonth < 1 || dayOfMonth > length) {
                throw DateTimeException("Invalid date: " + year + "-" + month + "-" + dayOfMonth)
            }
            return LocalDate(year, month, dayOfMonth)
        }

        public fun of(year: Int, month: Month, dayOfMonth: Int): LocalDate =
            of(year, month.value, dayOfMonth)

        public fun ofYearDay(year: Int, dayOfYear: Int): LocalDate {
            val max = if (javaTimeIsLeapYear(year)) 366 else 365
            if (dayOfYear < 1 || dayOfYear > max) {
                throw DateTimeException("Invalid value for DayOfYear: " + dayOfYear)
            }
            return ofEpochDay(javaTimeDaysFromCivil(year, 1, 1) + dayOfYear - 1L)
        }

        public fun ofEpochDay(epochDay: Long): LocalDate {
            val fields = javaTimeCivilFromDays(epochDay)
            return of(fields[0], fields[1], fields[2])
        }

        public fun parse(text: CharSequence): LocalDate {
            val value = text.toString()
            if (value.length != 10 || value[4] != '-' || value[7] != '-') {
                throw DateTimeException("Invalid ISO date: " + value)
            }
            return try {
                of(value.substring(0, 4).toInt(), value.substring(5, 7).toInt(), value.substring(8, 10).toInt())
            } catch (error: NumberFormatException) {
                throw DateTimeException("Invalid ISO date: " + value)
            }
        }
    }
}
