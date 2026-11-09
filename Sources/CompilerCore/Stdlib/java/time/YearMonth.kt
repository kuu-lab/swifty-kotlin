package java.time

/** A year and month in the ISO-8601 calendar system. */
public class YearMonth private constructor(
    public val year: Int,
    public val monthValue: Int,
) : Comparable<YearMonth> {
    public val month: Month
        get() = Month.of(monthValue)

    public fun getYear(): Int = year

    public fun getMonthValue(): Int = monthValue

    public fun getMonth(): Month = month

    public fun isLeapYear(): Boolean = javaTimeIsLeapYear(year)

    public fun lengthOfMonth(): Int = javaTimeLengthOfMonth(year, monthValue)

    public fun lengthOfYear(): Int = if (isLeapYear()) 366 else 365

    public fun isValidDay(dayOfMonth: Int): Boolean = dayOfMonth >= 1 && dayOfMonth <= lengthOfMonth()

    public fun atDay(dayOfMonth: Int): LocalDate = LocalDate.of(year, monthValue, dayOfMonth)

    public fun atEndOfMonth(): LocalDate = atDay(lengthOfMonth())

    public fun plusMonths(monthsToAdd: Long): YearMonth {
        val currentMonthCount = year.toLong() * 12L + monthValue - 1L
        val minimumMonthCount = -999_999_999L * 12L
        val maximumMonthCount = 999_999_999L * 12L + 11L
        if (monthsToAdd < minimumMonthCount - currentMonthCount ||
            monthsToAdd > maximumMonthCount - currentMonthCount
        ) {
            throw DateTimeException("Invalid value for YearMonth after adding: " + monthsToAdd)
        }
        val monthCount = currentMonthCount + monthsToAdd
        val newYear = javaTimeFloorDiv(monthCount, 12L)
        return of(newYear.toInt(), javaTimeFloorMod(monthCount, 12L).toInt() + 1)
    }

    public fun plusYears(yearsToAdd: Long): YearMonth {
        val minimumDelta = -999_999_999L - year
        val maximumDelta = 999_999_999L - year
        if (yearsToAdd < minimumDelta || yearsToAdd > maximumDelta) {
            throw DateTimeException("Invalid value for YearMonth after adding: " + yearsToAdd)
        }
        return of((year.toLong() + yearsToAdd).toInt(), monthValue)
    }

    public fun minusMonths(monthsToSubtract: Long): YearMonth {
        if (monthsToSubtract == Long.MIN_VALUE) {
            throw DateTimeException("Invalid value for YearMonth after subtracting: " + monthsToSubtract)
        }
        return plusMonths(-monthsToSubtract)
    }

    public fun minusYears(yearsToSubtract: Long): YearMonth {
        if (yearsToSubtract == Long.MIN_VALUE) {
            throw DateTimeException("Invalid value for YearMonth after subtracting: " + yearsToSubtract)
        }
        return plusYears(-yearsToSubtract)
    }

    public fun isBefore(other: YearMonth): Boolean = compareTo(other) < 0

    public fun isAfter(other: YearMonth): Boolean = compareTo(other) > 0

    override fun compareTo(other: YearMonth): Int {
        if (year != other.year) return year.compareTo(other.year)
        return monthValue.compareTo(other.monthValue)
    }

    override fun equals(other: Any?): Boolean =
        other is YearMonth && year == other.year && monthValue == other.monthValue

    override fun hashCode(): Int = year * 13 + monthValue

    override fun toString(): String = javaTimeFormatYear(year) + "-" + javaTimeTwoDigits(monthValue)

    public companion object {
        public val MIN: YearMonth = YearMonth(-999_999_999, 1)
        public val MAX: YearMonth = YearMonth(999_999_999, 12)

        public fun now(): YearMonth {
            val date = LocalDate.now()
            return of(date.year, date.monthValue)
        }

        public fun of(year: Int, month: Int): YearMonth {
            Year.of(year)
            if (month < 1 || month > 12) throw DateTimeException("Invalid value for MonthOfYear: " + month)
            return YearMonth(year, month)
        }

        public fun of(year: Int, month: Month): YearMonth = of(year, month.value)

        public fun parse(text: CharSequence): YearMonth {
            val value = text.toString()
            val separator = value.lastIndexOf('-')
            if (separator <= 0 || separator == value.length - 1) {
                throw DateTimeException("Invalid year-month: " + value)
            }
            return try {
                of(value.substring(0, separator).toInt(), value.substring(separator + 1).toInt())
            } catch (error: NumberFormatException) {
                throw DateTimeException("Invalid year-month: " + value)
            }
        }
    }
}
