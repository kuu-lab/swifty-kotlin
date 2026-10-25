package java.time

internal const val javaTimeNanosPerSecond: Long = 1_000_000_000L
internal const val javaTimeNanosPerMinute: Long = 60_000_000_000L
internal const val javaTimeNanosPerHour: Long = 3_600_000_000_000L
internal const val javaTimeNanosPerDay: Long = 86_400_000_000_000L
internal const val javaTimeSecondsPerDay: Long = 86_400L

internal fun javaTimeFloorDiv(value: Long, divisor: Long): Long {
    val quotient = value / divisor
    val remainder = value % divisor
    return if (remainder < 0L) quotient - 1L else quotient
}

internal fun javaTimeFloorMod(value: Long, divisor: Long): Long {
    val remainder = value % divisor
    return if (remainder < 0L) remainder + divisor else remainder
}

internal fun javaTimeIsLeapYear(year: Int): Boolean =
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

internal fun javaTimeLengthOfMonth(year: Int, month: Int): Int = when (month) {
    1, 3, 5, 7, 8, 10, 12 -> 31
    4, 6, 9, 11 -> 30
    2 -> if (javaTimeIsLeapYear(year)) 29 else 28
    else -> throw DateTimeException("Invalid value for MonthOfYear: " + month)
}

internal fun javaTimeDaysFromCivil(year: Int, month: Int, day: Int): Long {
    var adjustedYear = year.toLong()
    if (month <= 2) adjustedYear -= 1L
    val era = javaTimeFloorDiv(adjustedYear, 400L)
    val yearOfEra = adjustedYear - era * 400L
    val marchMonth = month + if (month > 2) -3 else 9
    val dayOfYear = (153 * marchMonth + 2) / 5 + day - 1
    val dayOfEra = yearOfEra * 365L + yearOfEra / 4L - yearOfEra / 100L + dayOfYear
    return era * 146_097L + dayOfEra - 719_468L
}

internal fun javaTimeCivilFromDays(epochDay: Long): IntArray {
    val shiftedDay = epochDay + 719_468L
    val era = javaTimeFloorDiv(shiftedDay, 146_097L)
    val dayOfEra = shiftedDay - era * 146_097L
    val yearOfEra = (dayOfEra - dayOfEra / 1_460L + dayOfEra / 36_524L - dayOfEra / 146_096L) / 365L
    var year = yearOfEra + era * 400L
    val dayOfYear = dayOfEra - (365L * yearOfEra + yearOfEra / 4L - yearOfEra / 100L)
    val marchMonth = (5L * dayOfYear + 2L) / 153L
    val day = dayOfYear - (153L * marchMonth + 2L) / 5L + 1L
    val month = marchMonth + if (marchMonth < 10L) 3L else -9L
    if (month <= 2L) year += 1L
    return intArrayOf(year.toInt(), month.toInt(), day.toInt())
}

internal fun javaTimeFormatYear(year: Int): String {
    val absoluteYear = if (year < 0) -year else year
    val digits = absoluteYear.toString()
    val padded = if (digits.length < 4) "0".repeat(4 - digits.length) + digits else digits
    return when {
        year < 0 -> "-" + padded
        year > 9_999 -> "+" + padded
        else -> padded
    }
}

internal fun javaTimeTwoDigits(value: Int): String =
    if (value < 10) "0" + value else value.toString()

public enum class Month(public val value: Int) {
    JANUARY(1),
    FEBRUARY(2),
    MARCH(3),
    APRIL(4),
    MAY(5),
    JUNE(6),
    JULY(7),
    AUGUST(8),
    SEPTEMBER(9),
    OCTOBER(10),
    NOVEMBER(11),
    DECEMBER(12);

    public fun getValue(): Int = value

    public fun length(leapYear: Boolean): Int = when (value) {
        2 -> if (leapYear) 29 else 28
        4, 6, 9, 11 -> 30
        else -> 31
    }

    public fun plus(months: Long): Month = of(javaTimeFloorMod(value.toLong() - 1L + months, 12L).toInt() + 1)

    public fun minus(months: Long): Month = plus(-months)

    public companion object {
        public fun of(month: Int): Month {
            if (month < 1 || month > 12) {
                throw DateTimeException("Invalid value for MonthOfYear: " + month)
            }
            return values()[month - 1]
        }
    }
}

public enum class DayOfWeek(public val value: Int) {
    MONDAY(1),
    TUESDAY(2),
    WEDNESDAY(3),
    THURSDAY(4),
    FRIDAY(5),
    SATURDAY(6),
    SUNDAY(7);

    public fun getValue(): Int = value

    public fun plus(days: Long): DayOfWeek = of(javaTimeFloorMod(value.toLong() - 1L + days, 7L).toInt() + 1)

    public fun minus(days: Long): DayOfWeek = plus(-days)

    public companion object {
        public fun of(dayOfWeek: Int): DayOfWeek {
            if (dayOfWeek < 1 || dayOfWeek > 7) {
                throw DateTimeException("Invalid value for DayOfWeek: " + dayOfWeek)
            }
            return values()[dayOfWeek - 1]
        }
    }
}

public open class DateTimeException : RuntimeException {
    public constructor() : super()

    public constructor(message: String?) : super(message)
}
