package java.time

/** A month and day in the ISO-8601 calendar system. */
public class MonthDay private constructor(
    public val monthValue: Int,
    public val dayOfMonth: Int,
) : Comparable<MonthDay> {
    public val month: Month
        get() = Month.of(monthValue)

    public fun getMonthValue(): Int = monthValue

    public fun getMonth(): Month = month

    public fun getDayOfMonth(): Int = dayOfMonth

    public fun isValidYear(year: Int): Boolean = dayOfMonth <= javaTimeLengthOfMonth(year, monthValue)

    public fun atYear(year: Int): LocalDate =
        LocalDate.of(year, monthValue, if (isValidYear(year)) dayOfMonth else 28)

    public fun isBefore(other: MonthDay): Boolean = compareTo(other) < 0

    public fun isAfter(other: MonthDay): Boolean = compareTo(other) > 0

    override fun compareTo(other: MonthDay): Int {
        if (monthValue != other.monthValue) return monthValue.compareTo(other.monthValue)
        return dayOfMonth.compareTo(other.dayOfMonth)
    }

    override fun equals(other: Any?): Boolean =
        other is MonthDay && monthValue == other.monthValue && dayOfMonth == other.dayOfMonth

    override fun hashCode(): Int = (monthValue shl 6) + dayOfMonth

    override fun toString(): String = "--" + javaTimeTwoDigits(monthValue) + "-" + javaTimeTwoDigits(dayOfMonth)

    public companion object {
        public val MIN: MonthDay = MonthDay(1, 1)
        public val MAX: MonthDay = MonthDay(12, 31)

        public fun now(): MonthDay {
            val date = LocalDate.now()
            return of(date.monthValue, date.dayOfMonth)
        }

        public fun of(month: Int, dayOfMonth: Int): MonthDay {
            if (month < 1 || month > 12) throw DateTimeException("Invalid value for MonthOfYear: " + month)
            val maxDay = javaTimeLengthOfMonth(2000, month)
            if (dayOfMonth < 1 || dayOfMonth > maxDay) {
                throw DateTimeException("Invalid value for DayOfMonth: " + dayOfMonth)
            }
            return MonthDay(month, dayOfMonth)
        }

        public fun of(month: Month, dayOfMonth: Int): MonthDay = of(month.value, dayOfMonth)

        public fun parse(text: CharSequence): MonthDay {
            val value = text.toString()
            if (value.length != 7 || !value.startsWith("--") || value[4] != '-') {
                throw DateTimeException("Invalid month-day: " + value)
            }
            return try {
                of(value.substring(2, 4).toInt(), value.substring(5, 7).toInt())
            } catch (error: NumberFormatException) {
                throw DateTimeException("Invalid month-day: " + value)
            }
        }
    }
}
