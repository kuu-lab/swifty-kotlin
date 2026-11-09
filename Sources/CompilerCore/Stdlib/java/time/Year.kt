package java.time

/** A year in the ISO-8601 calendar system. */
public class Year private constructor(
    public val value: Int,
) : Comparable<Year> {
    public val isLeap: Boolean
        get() = javaTimeIsLeapYear(value)

    public fun getValue(): Int = value

    public fun isLeapYear(): Boolean = isLeap

    public fun length(): Int = if (isLeap) 366 else 365

    public fun isValidMonthDay(monthDay: MonthDay): Boolean = monthDay.isValidYear(value)

    public fun atMonth(month: Month): YearMonth = YearMonth.of(value, month)

    public fun atMonth(month: Int): YearMonth = YearMonth.of(value, month)

    public fun atDay(dayOfYear: Int): LocalDate = LocalDate.ofYearDay(value, dayOfYear)

    public fun plusYears(yearsToAdd: Long): Year {
        val minimumDelta = -999_999_999L - value
        val maximumDelta = 999_999_999L - value
        if (yearsToAdd < minimumDelta || yearsToAdd > maximumDelta) {
            throw DateTimeException("Invalid value for Year after adding: " + yearsToAdd)
        }
        return of((value.toLong() + yearsToAdd).toInt())
    }

    public fun minusYears(yearsToSubtract: Long): Year {
        if (yearsToSubtract == Long.MIN_VALUE) {
            throw DateTimeException("Invalid value for Year after subtracting: " + yearsToSubtract)
        }
        return plusYears(-yearsToSubtract)
    }

    public fun isBefore(other: Year): Boolean = value < other.value

    public fun isAfter(other: Year): Boolean = value > other.value

    override fun compareTo(other: Year): Int = value.compareTo(other.value)

    override fun equals(other: Any?): Boolean = other is Year && value == other.value

    override fun hashCode(): Int = value

    override fun toString(): String = javaTimeFormatYear(value)

    public companion object {
        public val MIN: Year = Year(-999_999_999)
        public val MAX: Year = Year(999_999_999)

        public fun now(): Year = of(LocalDate.now().year)

        public fun of(isoYear: Int): Year {
            if (isoYear < -999_999_999 || isoYear > 999_999_999) {
                throw DateTimeException("Invalid value for Year: " + isoYear)
            }
            return Year(isoYear)
        }

        public fun parse(text: CharSequence): Year {
            val value = try {
                text.toString().toInt()
            } catch (error: NumberFormatException) {
                throw DateTimeException("Invalid year: " + text)
            }
            return of(value)
        }
    }
}
