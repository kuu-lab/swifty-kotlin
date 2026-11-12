package kotlin.time

internal fun instantEpochMilliseconds(instant: Instant): Long {
    if (instant.epochSeconds >= 0) {
        val nanosAsMillis = (instant.nanosecondsOfSecond / 1_000_000).toLong()
        if (instant.epochSeconds > instantLongMaxValue() / 1_000L) return instantLongMaxValue()
        val millis = instant.epochSeconds * 1_000L
        if (millis > instantLongMaxValue() - nanosAsMillis) return instantLongMaxValue()
        return millis + nanosAsMillis
    }

    val adjustedEpochSeconds = instant.epochSeconds + 1L
    val nanosAdjustment = (instant.nanosecondsOfSecond / 1_000_000 - 1_000).toLong()
    if (adjustedEpochSeconds < instantLongMinValue() / 1_000L) return instantLongMinValue()
    val millis = adjustedEpochSeconds * 1_000L
    if (millis < instantLongMinValue() - nanosAdjustment) return instantLongMinValue()
    return millis + nanosAdjustment
}

private fun instantLongMaxValue(): Long = 9223372036854775807L

private fun instantLongMinValue(): Long = -9223372036854775807L - 1L

private class InstantLocalDateTime(
    val year: Long,
    val month: Int,
    val day: Int,
    val hour: Int,
    val minute: Int,
    val second: Int,
    val nanosecond: Int,
)

private fun instantLocalDateTimeFromInstant(instant: Instant): InstantLocalDateTime {
    val secondsPerDay = 86_400L
    val epochDays = instantFloorDiv(instant.epochSeconds, secondsPerDay)
    val secondsOfDay = (instant.epochSeconds - epochDays * secondsPerDay).toInt()

    var zeroDay = epochDays + 719_528L
    zeroDay -= 60L
    var adjust = 0L
    if (zeroDay < 0) {
        val adjustCycles = (zeroDay + 1L) / 146_097L - 1L
        adjust = adjustCycles * 400L
        zeroDay += -adjustCycles * 146_097L
    }
    var yearEstimate = (400L * zeroDay + 591L) / 146_097L
    var dayOfYearEstimate = zeroDay -
        (365L * yearEstimate + yearEstimate / 4L - yearEstimate / 100L + yearEstimate / 400L)
    if (dayOfYearEstimate < 0) {
        yearEstimate -= 1L
        dayOfYearEstimate = zeroDay -
            (365L * yearEstimate + yearEstimate / 4L - yearEstimate / 100L + yearEstimate / 400L)
    }
    yearEstimate += adjust
    val marchDayOfYear = dayOfYearEstimate.toInt()
    val marchMonth = (marchDayOfYear * 5 + 2) / 153
    val month = (marchMonth + 2) % 12 + 1
    val day = marchDayOfYear - (marchMonth * 306 + 5) / 10 + 1
    val year = yearEstimate + marchMonth / 10

    val hour = secondsOfDay / 3_600
    val secondWithoutHours = secondsOfDay - hour * 3_600
    val minute = secondWithoutHours / 60
    val second = secondWithoutHours - minute * 60
    return InstantLocalDateTime(
        year,
        month,
        day,
        hour,
        minute,
        second,
        instant.nanosecondsOfSecond,
    )
}

internal fun instantFormatIso(instant: Instant): String {
    val local = instantLocalDateTimeFromInstant(instant)
    val builder = StringBuilder()
    val year = local.year
    when {
        year >= 0L && year < 1_000L -> builder.append((year + 10_000L).toString().substring(1))
        year < 0L && year > -1_000L -> {
            builder.append('-')
            builder.append((-year + 10_000L).toString().substring(1))
        }
        else -> {
            if (year >= 10_000L) builder.append('+')
            builder.append(year)
        }
    }
    builder.append('-')
    instantAppendTwoDigits(builder, local.month)
    builder.append('-')
    instantAppendTwoDigits(builder, local.day)
    builder.append('T')
    instantAppendTwoDigits(builder, local.hour)
    builder.append(':')
    instantAppendTwoDigits(builder, local.minute)
    builder.append(':')
    instantAppendTwoDigits(builder, local.second)
    if (local.nanosecond != 0) {
        builder.append('.')
        val (fraction, digits) = when {
            local.nanosecond % 1_000_000 == 0 -> local.nanosecond / 1_000_000 to 3
            local.nanosecond % 1_000 == 0 -> local.nanosecond / 1_000 to 6
            else -> local.nanosecond to 9
        }
        builder.append((fraction + instantPowerOfTen(digits)).toString().substring(1))
    }
    builder.append('Z')
    return builder.toString()
}

private fun instantAppendTwoDigits(builder: StringBuilder, number: Int) {
    if (number < 10) builder.append('0')
    builder.append(number)
}

private fun instantPowerOfTen(digits: Int): Int = when (digits) {
    3 -> 1_000
    6 -> 1_000_000
    else -> 1_000_000_000
}

private fun instantFloorDiv(value: Long, divisor: Long): Long {
    val quotient = value / divisor
    val remainder = value % divisor
    return if (remainder < 0L) quotient - 1L else quotient
}
