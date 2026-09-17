package kotlin.time

import kotlin.internal.KsSymbolName

// KSP-1490: construction from epoch components is kept in Kotlin source. The
// runtime bridge only allocates and normalizes the opaque native Instant box.
@KsSymbolName("kk_instant_from_epoch_seconds")
private external fun __kk_instant_from_epoch_seconds(
    epochSeconds: Long,
    nanosecondAdjustment: Long
): Instant

private const val INSTANT_NANOS_PER_SECOND: Long = 1_000_000_000L
private const val INSTANT_SECONDS_PER_DAY: Long = 86_400L
private const val INSTANT_MIN_SECOND: Long = -31_557_014_167_219_200L
private const val INSTANT_MAX_SECOND: Long = 31_556_889_864_403_199L
private const val INSTANT_DISTANT_PAST_SECONDS: Long = -3_217_862_419_201L
private const val INSTANT_DISTANT_FUTURE_SECONDS: Long = 3_093_527_980_800L

public val Instant.Companion.DISTANT_PAST: Instant
    get() = instantFromEpochSeconds(INSTANT_DISTANT_PAST_SECONDS, 999_999_999L)

public val Instant.Companion.DISTANT_FUTURE: Instant
    get() = instantFromEpochSeconds(INSTANT_DISTANT_FUTURE_SECONDS, 0L)

public fun Instant.Companion.fromEpochSeconds(
    epochSeconds: Long,
    nanosecondAdjustment: Long = 0L
): Instant = instantFromEpochSeconds(epochSeconds, nanosecondAdjustment)

private fun instantFromEpochSeconds(epochSeconds: Long, nanosecondAdjustment: Long): Instant {
    val secondsAdjustment = instantFloorDiv(nanosecondAdjustment, INSTANT_NANOS_PER_SECOND)
    val normalizedSeconds = instantSaturatingAdd(epochSeconds, secondsAdjustment)
    if (normalizedSeconds < INSTANT_MIN_SECOND) {
        return __kk_instant_from_epoch_seconds(INSTANT_MIN_SECOND, 0L)
    }
    if (normalizedSeconds > INSTANT_MAX_SECOND) {
        return __kk_instant_from_epoch_seconds(INSTANT_MAX_SECOND, 999_999_999L)
    }
    val normalizedNanos = nanosecondAdjustment - secondsAdjustment * INSTANT_NANOS_PER_SECOND
    return __kk_instant_from_epoch_seconds(normalizedSeconds, normalizedNanos)
}

public fun Instant.Companion.fromEpochSeconds(
    epochSeconds: Long,
    nanosecondAdjustment: Int
): Instant = instantFromEpochSeconds(epochSeconds, nanosecondAdjustment.toLong())

public fun Instant.Companion.parse(input: CharSequence): Instant {
    return instantParseOrNull(input.toString())
        ?: throw IllegalArgumentException("Invalid instant string: $input")
}

public fun Instant.Companion.parseOrNull(input: CharSequence): Instant? =
    instantParseOrNull(input.toString())

private fun instantParseOrNull(text: String): Instant? {
    if (text.isEmpty()) return null
    var index = 0
    var yearSign = 1L
    if (text[index] == '+' || text[index] == '-') {
        if (text[index] == '-') yearSign = -1L
        index += 1
    }

    val yearStart = index
    var absoluteYear = 0L
    while (index < text.length && text[index] >= '0' && text[index] <= '9') {
        if (absoluteYear > 1_000_000_000L) return null
        absoluteYear = absoluteYear * 10L + (text[index] - '0').toLong()
        index += 1
    }
    val yearDigits = index - yearStart
    if (yearDigits < 4 || yearDigits > 10 || index >= text.length || text[index] != '-') return null
    val year = yearSign * absoluteYear
    index += 1

    val month = instantReadTwoDigits(text, index) ?: return null
    index += 2
    if (index >= text.length || text[index] != '-') return null
    index += 1
    val day = instantReadTwoDigits(text, index) ?: return null
    index += 2
    if (index >= text.length || (text[index] != 'T' && text[index] != 't')) return null
    index += 1

    val hour = instantReadTwoDigits(text, index) ?: return null
    index += 2
    if (index >= text.length || text[index] != ':') return null
    index += 1
    val minute = instantReadTwoDigits(text, index) ?: return null
    index += 2
    if (index >= text.length || text[index] != ':') return null
    index += 1
    val second = instantReadTwoDigits(text, index) ?: return null
    index += 2

    var nanosecond = 0
    if (index < text.length && text[index] == '.') {
        index += 1
        val fractionStart = index
        while (index < text.length && text[index] >= '0' && text[index] <= '9') {
            if (index - fractionStart >= 9) return null
            nanosecond = nanosecond * 10 + (text[index] - '0')
            index += 1
        }
        val fractionDigits = index - fractionStart
        if (fractionDigits == 0) return null
        var padding = fractionDigits
        while (padding < 9) {
            nanosecond *= 10
            padding += 1
        }
    }

    var offsetSeconds = 0
    if (index >= text.length) return null
    if (text[index] == 'Z' || text[index] == 'z') {
        index = index + 1
    } else if (text[index] == '+' || text[index] == '-') {
        val offsetSign = if (text[index] == '-') -1 else 1
        index += 1
        val offsetHours = instantReadTwoDigits(text, index) ?: return null
        index += 2
        var offsetMinutes = 0
        var offsetExtraSeconds = 0
        if (index < text.length && text[index] == ':') {
            index += 1
            offsetMinutes = instantReadTwoDigits(text, index) ?: return null
            index += 2
            if (index < text.length && text[index] == ':') {
                index += 1
                offsetExtraSeconds = instantReadTwoDigits(text, index) ?: return null
                index += 2
            }
        }
        if (offsetHours > 23 || offsetMinutes > 59 || offsetExtraSeconds > 59) return null
        offsetSeconds = offsetSign * (offsetHours * 3_600 + offsetMinutes * 60 + offsetExtraSeconds)
    } else {
        return null
    }
    if (index != text.length) return null
    if (month < 1 || month > 12 || day < 1 || day > instantDaysInMonth(year, month)) return null
    if (hour > 23 || minute > 59 || second > 59) return null

    val epochDay = instantEpochDay(year, month, day)
    val localSeconds = epochDay * INSTANT_SECONDS_PER_DAY +
        hour * 3_600L + minute * 60L + second.toLong()
    val epochSeconds = localSeconds - offsetSeconds.toLong()
    if (epochSeconds < INSTANT_MIN_SECOND || epochSeconds > INSTANT_MAX_SECOND) return null
    return instantFromEpochSeconds(epochSeconds, nanosecond.toLong())
}

private fun instantReadTwoDigits(text: String, index: Int): Int? {
    if (index < 0 || index + 1 >= text.length) return null
    val first = text[index]
    val second = text[index + 1]
    if (first < '0' || first > '9' || second < '0' || second > '9') return null
    return (first - '0') * 10 + (second - '0')
}

private fun instantIsLeapYear(year: Long): Boolean =
    (year % 4L == 0L && year % 100L != 0L) || year % 400L == 0L

private fun instantDaysInMonth(year: Long, month: Int): Int = when (month) {
    2 -> if (instantIsLeapYear(year)) 29 else 28
    4, 6, 9, 11 -> 30
    else -> 31
}

private fun instantEpochDay(year: Long, month: Int, day: Int): Long {
    var total = 365L * year
    if (year >= 0L) {
        total += (year + 3L) / 4L - (year + 99L) / 100L + (year + 399L) / 400L
    } else {
        total -= year / -4L - year / -100L + year / -400L
    }
    total += (367L * month - 362L) / 12L
    total += day - 1L
    if (month > 2) {
        total -= 1L
        if (!instantIsLeapYear(year)) total -= 1L
    }
    return total - 719_528L
}

private fun instantFloorDiv(value: Long, divisor: Long): Long {
    val quotient = value / divisor
    val remainder = value % divisor
    return if (remainder < 0L) quotient - 1L else quotient
}

private fun instantSaturatingAdd(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}
