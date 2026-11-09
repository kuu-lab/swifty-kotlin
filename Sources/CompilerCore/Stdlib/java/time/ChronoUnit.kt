package java.time

/** Standard date and time units used to measure temporal amounts. */
public enum class ChronoUnit(public val unitCode: Int) {
    NANOS(0),
    MICROS(1),
    MILLIS(2),
    SECONDS(3),
    MINUTES(4),
    HOURS(5),
    HALF_DAYS(6),
    DAYS(7),
    WEEKS(8),
    MONTHS(9),
    YEARS(10),
    DECADES(11),
    CENTURIES(12),
    MILLENNIA(13),
    ERAS(14),
    FOREVER(15);

    public fun between(startInclusive: LocalDate, endExclusive: LocalDate): Long = when (unitCode) {
        7 -> endExclusive.toEpochDay() - startInclusive.toEpochDay()
        8 -> (endExclusive.toEpochDay() - startInclusive.toEpochDay()) / 7L
        9 -> javaTimeMonthsBetween(startInclusive, endExclusive)
        10 -> javaTimeMonthsBetween(startInclusive, endExclusive) / 12L
        11 -> javaTimeMonthsBetween(startInclusive, endExclusive) / 120L
        12 -> javaTimeMonthsBetween(startInclusive, endExclusive) / 1_200L
        13 -> javaTimeMonthsBetween(startInclusive, endExclusive) / 12_000L
        14 -> (if (endExclusive.year >= 1) 1L else 0L) - (if (startInclusive.year >= 1) 1L else 0L)
        15 -> throw UnsupportedOperationException("Forever cannot be used to measure a date")
        else -> throw DateTimeException("Unsupported unit for LocalDate: " + this)
    }

    public fun between(startInclusive: LocalDateTime, endExclusive: LocalDateTime): Long = when (unitCode) {
        7 -> javaTimeLocalDaysBetween(startInclusive, endExclusive)
        8 -> javaTimeLocalDaysBetween(startInclusive, endExclusive) / 7L
        9 -> javaTimeLocalMonthsBetween(startInclusive, endExclusive)
        10 -> javaTimeLocalMonthsBetween(startInclusive, endExclusive) / 12L
        11 -> javaTimeLocalMonthsBetween(startInclusive, endExclusive) / 120L
        12 -> javaTimeLocalMonthsBetween(startInclusive, endExclusive) / 1_200L
        13 -> javaTimeLocalMonthsBetween(startInclusive, endExclusive) / 12_000L
        14 -> (if (endExclusive.year >= 1) 1L else 0L) - (if (startInclusive.year >= 1) 1L else 0L)
        else -> javaTimeBetweenInstants(
            startInclusive.date.toEpochDay() * javaTimeSecondsPerDay + startInclusive.time.secondOfDay,
            startInclusive.nano,
            endExclusive.date.toEpochDay() * javaTimeSecondsPerDay + endExclusive.time.secondOfDay,
            endExclusive.nano,
            unitCode
        )
    }

    public fun between(startInclusive: Instant, endExclusive: Instant): Long =
        javaTimeBetweenInstants(startInclusive.epochSecond, startInclusive.nano, endExclusive.epochSecond, endExclusive.nano, unitCode)

    public fun between(startInclusive: OffsetDateTime, endExclusive: OffsetDateTime): Long {
        return if (javaTimeUnitIsDateBased(unitCode)) {
            between(startInclusive.toLocalDateTime(), endExclusive.toLocalDateTime())
        } else {
            between(startInclusive.toInstant(), endExclusive.toInstant())
        }
    }

    public fun between(startInclusive: ZonedDateTime, endExclusive: ZonedDateTime): Long {
        return if (javaTimeUnitIsDateBased(unitCode)) {
            between(startInclusive.toLocalDateTime(), endExclusive.toLocalDateTime())
        } else {
            between(startInclusive.toInstant(), endExclusive.toInstant())
        }
    }
}

private fun javaTimeMonthsBetween(start: LocalDate, end: LocalDate): Long {
    var months = (end.year - start.year).toLong() * 12L + end.monthValue - start.monthValue
    if (months > 0L && end.dayOfMonth < start.dayOfMonth) months -= 1L
    else if (months < 0L && end.dayOfMonth > start.dayOfMonth) months += 1L
    return months
}

private fun javaTimeLocalDaysBetween(start: LocalDateTime, end: LocalDateTime): Long {
    var days = end.date.toEpochDay() - start.date.toEpochDay()
    if (days > 0L && end.time.compareTo(start.time) < 0) days -= 1L
    else if (days < 0L && end.time.compareTo(start.time) > 0) days += 1L
    return days
}

private fun javaTimeLocalMonthsBetween(start: LocalDateTime, end: LocalDateTime): Long {
    var months = javaTimeMonthsBetween(start.date, end.date)
    if (months > 0L && end.date.dayOfMonth == start.date.dayOfMonth && end.time.compareTo(start.time) < 0) months -= 1L
    else if (months < 0L && end.date.dayOfMonth == start.date.dayOfMonth && end.time.compareTo(start.time) > 0) months += 1L
    return months
}

private fun javaTimeUnitIsDateBased(unitCode: Int): Boolean =
    unitCode == 7 || unitCode == 8 || unitCode == 9 || unitCode == 10 || unitCode == 11 ||
        unitCode == 12 || unitCode == 13 || unitCode == 14

private fun javaTimeBetweenInstants(
    startSecond: Long,
    startNano: Int,
    endSecond: Long,
    endNano: Int,
    unitCode: Int,
): Long {
    var seconds = endSecond - startSecond
    var nanos = endNano - startNano
    if (seconds > 0L && nanos < 0) {
        seconds -= 1L
        nanos += 1_000_000_000
    } else if (seconds < 0L && nanos > 0) {
        seconds += 1L
        nanos -= 1_000_000_000
    }
    return when (unitCode) {
        0 -> seconds * javaTimeNanosPerSecond + nanos
        1 -> seconds * 1_000_000L + nanos / 1_000
        2 -> seconds * 1_000L + nanos / 1_000_000
        3 -> seconds
        4 -> seconds / 60L
        5 -> seconds / 3_600L
        6 -> seconds / 43_200L
        7 -> seconds / javaTimeSecondsPerDay
        15 -> throw UnsupportedOperationException("Forever cannot be used to measure a temporal amount")
        else -> throw DateTimeException("Unsupported time-based unit: " + unitCode)
    }
}
