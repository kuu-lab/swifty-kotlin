package java.time

/** A date-based amount of time measured in years, months, and days. */
public class Period private constructor(
    public val years: Int,
    public val months: Int,
    public val days: Int,
) {
    public fun getYears(): Int = years

    public fun getMonths(): Int = months

    public fun getDays(): Int = days

    public fun isZero(): Boolean = years == 0 && months == 0 && days == 0

    public fun isNegative(): Boolean = years < 0 || months < 0 || days < 0

    public fun toTotalMonths(): Long = years.toLong() * 12L + months

    public fun plus(other: Period): Period = of(
        years + other.years,
        months + other.months,
        days + other.days
    )

    public fun minus(other: Period): Period = of(
        years - other.years,
        months - other.months,
        days - other.days
    )

    public fun multipliedBy(scalar: Int): Period = of(years * scalar, months * scalar, days * scalar)

    public fun negated(): Period = multipliedBy(-1)

    public fun normalized(): Period {
        val totalMonths = toTotalMonths()
        val normalizedYears = (totalMonths / 12L).toInt()
        val normalizedMonths = (totalMonths % 12L).toInt()
        return of(normalizedYears, normalizedMonths, days)
    }

    public fun withYears(newYears: Int): Period = of(newYears, months, days)

    public fun withMonths(newMonths: Int): Period = of(years, newMonths, days)

    public fun withDays(newDays: Int): Period = of(years, months, newDays)

    override fun equals(other: Any?): Boolean =
        other is Period && years == other.years && months == other.months && days == other.days

    override fun hashCode(): Int = years + months * 13 + days * 31

    override fun toString(): String {
        if (isZero()) return "P0D"
        val builder = StringBuilder("P")
        if (years != 0) builder.append(years).append('Y')
        if (months != 0) builder.append(months).append('M')
        if (days != 0) builder.append(days).append('D')
        return builder.toString()
    }

    public companion object {
        public val ZERO: Period = Period(0, 0, 0)

        public fun of(years: Int, months: Int, days: Int): Period =
            if (years == 0 && months == 0 && days == 0) ZERO else Period(years, months, days)

        public fun ofYears(years: Int): Period = of(years, 0, 0)

        public fun ofMonths(months: Int): Period = of(0, months, 0)

        public fun ofWeeks(weeks: Int): Period = of(0, 0, weeks * 7)

        public fun ofDays(days: Int): Period = of(0, 0, days)

        public fun between(startDateInclusive: LocalDate, endDateExclusive: LocalDate): Period {
            var totalMonths = (endDateExclusive.year - startDateInclusive.year).toLong() * 12L
            totalMonths += endDateExclusive.monthValue - startDateInclusive.monthValue
            var days = endDateExclusive.dayOfMonth - startDateInclusive.dayOfMonth
            if (totalMonths > 0L && days < 0) {
                totalMonths -= 1L
                days = (endDateExclusive.toEpochDay() - startDateInclusive.plusMonths(totalMonths).toEpochDay()).toInt()
            } else if (totalMonths < 0L && days > 0) {
                totalMonths += 1L
                days = (endDateExclusive.toEpochDay() - startDateInclusive.plusMonths(totalMonths).toEpochDay()).toInt()
            }
            return of((totalMonths / 12L).toInt(), (totalMonths % 12L).toInt(), days)
        }
    }
}
