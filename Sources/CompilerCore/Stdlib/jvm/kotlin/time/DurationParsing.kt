package kotlin.time

import kotlin.math.roundToLong

// Faithful port of the kotlin-stdlib 2.4.20 Duration parsing pipeline
// (parseDuration / parseIsoStringFormat / parseDefaultStringFormat with
// LongParser and FractionalParser): exact decimal digit arithmetic for
// fractional components, saturating long conversion clamped to MAX_MILLIS,
// and millisecond/nanosecond split accumulation whose infinity conflicts
// invalidate ISO input.

private const val DURATION_PARSE_FRACTION_LIMIT: Int = 15
private const val DURATION_PARSE_INVALID_MILLIS: Long = Long.MIN_VALUE
private const val DURATION_PARSE_INFINITY_STRING: String = "infinity"

private class DurationLongParse(
    val endIndex: Int,
    val sign: Int,
    val hasOverflow: Boolean,
    val value: Long,
)

private class DurationFractionParse(
    val endIndex: Int,
    val digits: Long,
)

private fun durationParseLong(value: String, startIndex: Int, overflowLimit: Long, allowSign: Boolean): DurationLongParse {
    var sign = 1
    var index = startIndex
    if (allowSign) {
        val firstChar = value[index]
        if (firstChar == '-') {
            sign = -1
            index += 1
        } else if (firstChar == '+') {
            index += 1
        }
    }
    while (index < value.length && value[index] == '0') {
        index += 1
    }
    val overflowThreshold = overflowLimit / 10L
    val lastDigitMax = overflowLimit % 10L
    var result = 0L
    while (index < value.length) {
        val ch = value[index]
        if (ch < '0' || ch > '9') break
        val digit = (ch - '0').toLong()
        if (result > overflowThreshold || (result == overflowThreshold && digit > lastDigitMax)) {
            while (index < value.length && value[index] >= '0' && value[index] <= '9') {
                index += 1
            }
            return DurationLongParse(index, sign, true, overflowLimit)
        }
        result = result * 10L + digit
        index += 1
    }
    return DurationLongParse(index, sign, false, result)
}

private fun durationParseDigits(value: String, startIndex: Int, maxDigits: Int): Pair<Int, Int> {
    var index = startIndex
    val endIndex = minOf(index + maxDigits, value.length)
    var result = 0
    while (index < endIndex) {
        val ch = value[index]
        if (ch < '0' || ch > '9') break
        result = result * 10 + (ch - '0')
        index += 1
    }
    var padding = maxDigits - (index - startIndex)
    while (padding > 0) {
        result *= 10
        padding -= 1
    }
    return Pair(index, result)
}

private fun durationParseFraction(value: String, startIndex: Int): DurationFractionParse {
    var index = startIndex
    val high = durationParseDigits(value, index, DURATION_PARSE_FRACTION_LIMIT - 9)
    index = high.first
    val low = durationParseDigits(value, index, 9)
    index = low.first
    while (index < value.length && value[index] >= '0' && value[index] <= '9') {
        index += 1
    }
    return DurationFractionParse(index, high.second.toLong() * 1_000_000_000L + low.second)
}

private fun durationFractionDigitsToNanos(fractionDigits: Long, multiplier: Double): Long =
    (fractionDigits * multiplier).roundToLong()

private fun durationUnitFractionMultiplier(unit: DurationUnit): Double = when (unit) {
    DurationUnit.NANOSECONDS -> 0.000000000000001
    DurationUnit.MICROSECONDS -> 0.000000000001
    DurationUnit.MILLISECONDS -> 0.000000001
    DurationUnit.SECONDS -> 0.000001
    DurationUnit.MINUTES -> 0.00006
    DurationUnit.HOURS -> 0.0036
    DurationUnit.DAYS -> 0.0864
}

private fun durationUnitFallbackFractionMultiplier(unit: DurationUnit): Long = when (unit) {
    DurationUnit.MINUTES -> 60_000_000_000L
    DurationUnit.HOURS -> 3_600_000_000_000L
    DurationUnit.DAYS -> 86_400_000_000_000L
    else -> 1L
}

private fun durationUnitShortNameLength(unit: DurationUnit): Int = when (unit) {
    DurationUnit.MILLISECONDS, DurationUnit.MICROSECONDS, DurationUnit.NANOSECONDS -> 2
    else -> 1
}

private fun durationUnitMillisMultiplier(unit: DurationUnit): Long = when (unit) {
    DurationUnit.DAYS -> 86_400_000L
    DurationUnit.HOURS -> 3_600_000L
    DurationUnit.MINUTES -> 60_000L
    DurationUnit.SECONDS -> 1_000L
    DurationUnit.MILLISECONDS -> 1L
    else -> 0L
}

// convertDurationUnitToMilliseconds: the input is always non-negative here;
// overflow of the positive multiplication saturates to MAX_MILLIS.
private fun durationConvertToMilliseconds(value: Long, unit: DurationUnit): Long {
    val multiplier = durationUnitMillisMultiplier(unit)
    if (value == 0L) return 0L
    if (multiplier == 1L) return if (value > MAX_MILLIS) MAX_MILLIS else value
    if (value > MAX_MILLIS / multiplier) return MAX_MILLIS
    val product = value * multiplier
    return if (product > MAX_MILLIS) MAX_MILLIS else product
}

private fun durationIsInfiniteMillis(value: Long): Boolean = value == MAX_MILLIS || value == -MAX_MILLIS

// addMillisWithoutOverflow; DURATION_PARSE_INVALID_MILLIS stands in for
// Duration.INVALID_RAW_VALUE, which no representable millisecond total can equal.
private fun durationAddMillis(lhs: Long, rhs: Long): Long {
    if (durationIsInfiniteMillis(lhs)) {
        val rhsFinite = rhs > -MAX_MILLIS && rhs < MAX_MILLIS
        if (rhsFinite || (lhs xor rhs) >= 0L) return lhs
        return DURATION_PARSE_INVALID_MILLIS
    }
    if (durationIsInfiniteMillis(rhs)) return rhs
    val sum = lhs + rhs
    if (sum > MAX_MILLIS) return MAX_MILLIS
    if (sum < -MAX_MILLIS) return -MAX_MILLIS
    return sum
}

private fun durationIsoUnitByShortName(value: String, index: Int): DurationUnit? = when (value[index]) {
    'D' -> DurationUnit.DAYS
    'H' -> DurationUnit.HOURS
    'M' -> DurationUnit.MINUTES
    'S' -> DurationUnit.SECONDS
    else -> null
}

private fun durationDefaultUnitByShortName(value: String, index: Int): DurationUnit? {
    val first = value[index]
    val second = if (index + 1 < value.length) value[index + 1] else ' '
    return when (first) {
        'd' -> DurationUnit.DAYS
        'h' -> DurationUnit.HOURS
        's' -> DurationUnit.SECONDS
        'm' -> if (second == 's') DurationUnit.MILLISECONDS else DurationUnit.MINUTES
        'u' -> if (second == 's') DurationUnit.MICROSECONDS else null
        'n' -> if (second == 's') DurationUnit.NANOSECONDS else null
        else -> null
    }
}

private fun durationParseIsoFormat(value: String, startIndex: Int): Long? {
    var index = startIndex
    if (index == value.length) return null

    var totalMillis = 0L
    var totalNanos = 0L
    var isTimeComponent = false
    var prevUnit: DurationUnit? = null

    while (index < value.length) {
        val ch = value[index]
        if (ch == 'T') {
            if (isTimeComponent) return null
            index += 1
            if (index == value.length) return null
            isTimeComponent = true
            continue
        }

        val longStartIndex = index
        val longParse = durationParseLong(value, index, MAX_MILLIS, allowSign = true)
        index = longParse.endIndex
        val signOffset = if (ch == '-' || ch == '+') 1 else 0
        if (index == value.length || index == longStartIndex + signOffset) return null
        val sign = longParse.sign
        val longValue = longParse.value

        if (value[index] == '.') {
            index += 1
            val fraction = durationParseFraction(value, index)
            if (fraction.endIndex == index || fraction.endIndex == value.length) return null
            if (value[fraction.endIndex] != 'S') return null
            index = fraction.endIndex
            totalNanos = sign * durationFractionDigitsToNanos(fraction.digits, durationUnitFractionMultiplier(DurationUnit.SECONDS))
        }

        val unit = durationIsoUnitByShortName(value, index) ?: return null
        if (prevUnit != null && prevUnit <= unit) return null
        prevUnit = unit

        if (unit == DurationUnit.DAYS) {
            if (isTimeComponent) return null
            totalMillis = sign * durationConvertToMilliseconds(longValue, unit)
        } else {
            if (!isTimeComponent) return null
            totalMillis = durationAddMillis(totalMillis, sign * durationConvertToMilliseconds(longValue, unit))
            if (totalMillis == DURATION_PARSE_INVALID_MILLIS) return null
        }

        index += 1
    }

    if (prevUnit == null) return null
    return combineDurationParseResult(totalMillis, totalNanos)
}

private fun durationParseDefaultFormat(value: String, startIndex: Int, hasSign: Boolean): Long? {
    var index = startIndex
    var length = value.length
    var allowSpaces = !hasSign

    if (hasSign && value[index] == '(' && value[length - 1] == ')') {
        allowSpaces = true
        index += 1
        length -= 1
        if (index == length) return null
    }

    var totalMillis = 0L
    var totalNanos = 0L
    var prevUnit: DurationUnit? = null
    var isFirstComponent = true

    while (index < length) {
        if (!isFirstComponent && allowSpaces) {
            while (index < length && value[index] == ' ') {
                index += 1
            }
        }
        isFirstComponent = false

        val longStartIndex = index
        val longParse = durationParseLong(value, index, Long.MAX_VALUE, allowSign = false)
        if (longParse.endIndex == longStartIndex || longParse.endIndex == length || longParse.hasOverflow) return null
        index = longParse.endIndex
        val longValue = longParse.value

        val hasFractionalPart = value[index] == '.'
        var fractionStartIndex = -1
        var fractionDigits = 0L
        if (hasFractionalPart) {
            fractionStartIndex = index
            index += 1
            val fraction = durationParseFraction(value, index)
            if (fraction.endIndex == index || fraction.endIndex == length) return null
            index = fraction.endIndex
            fractionDigits = fraction.digits
        }

        val unit = durationDefaultUnitByShortName(value, index) ?: return null
        if (prevUnit != null && prevUnit <= unit) return null
        prevUnit = unit

        if (unit == DurationUnit.MICROSECONDS) {
            totalMillis += longValue / 1_000L
            if (totalMillis <= MAX_NANOS / NANOS_PER_MILLISECOND) {
                totalNanos = (longValue % 1_000L) * 1_000L
            }
        } else if (unit == DurationUnit.NANOSECONDS) {
            totalMillis += longValue / NANOS_PER_MILLISECOND
            totalNanos += longValue % NANOS_PER_MILLISECOND
        } else {
            totalMillis = durationAddMillis(totalMillis, durationConvertToMilliseconds(longValue, unit))
        }

        index += durationUnitShortNameLength(unit)

        if (hasFractionalPart) {
            if (index < length) return null
            totalNanos += if (unit >= DurationUnit.MINUTES && index - fractionStartIndex > DURATION_PARSE_FRACTION_LIMIT) {
                val fractionText = value.substring(fractionStartIndex, index - durationUnitShortNameLength(unit))
                (fractionText.toDouble() * durationUnitFallbackFractionMultiplier(unit).toDouble()).roundToLong()
            } else {
                durationFractionDigitsToNanos(fractionDigits, durationUnitFractionMultiplier(unit))
            }
        }
    }

    return combineDurationParseResult(totalMillis, totalNanos)
}

private fun combineDurationParseResult(totalMillis: Long, totalNanos: Long): Long {
    val millisDuration = durationRawFromLong(totalMillis, DurationUnit.MILLISECONDS)
    val nanosDuration = durationRawFromLong(totalNanos, DurationUnit.NANOSECONDS)
    return addDurationRaw(millisDuration, nanosDuration)
}

// Case-insensitive comparison specialized for the fixed ASCII literal
// "infinity". Kotlin's ignore-case Char comparison also folds the dotted and
// dotless Turkish I variants to ASCII I; spelling this out keeps the parser
// independent of target-specific Unicode case-conversion tables.
private fun durationInfinityCharEquals(value: Char, expected: Char): Boolean {
    if (value == expected) return true
    if (expected == 'i') return value == 'I' || value == 'ı' || value == 'İ'
    return when (expected) {
        'n' -> value == 'N'
        'f' -> value == 'F'
        't' -> value == 'T'
        'y' -> value == 'Y'
        else -> false
    }
}

private fun durationIsInfinityLiteral(value: String, startIndex: Int): Boolean {
    val length = DURATION_PARSE_INFINITY_STRING.length
    if (value.length - startIndex != length) return false
    var offset = 0
    while (offset < length) {
        if (!durationInfinityCharEquals(value[startIndex + offset], DURATION_PARSE_INFINITY_STRING[offset])) return false
        offset += 1
    }
    return true
}

internal fun durationParseRawOrNull(value: String, strictIso: Boolean): Long? {
    if (value.isEmpty()) return null
    var index = 0
    var isNegative = false
    if (value[index] == '-') {
        isNegative = true
        index += 1
    } else if (value[index] == '+') {
        index += 1
    }
    val hasSign = index > 0
    if (value.length <= index) return null

    val parsed: Long?
    if (value[index] == 'P') {
        parsed = durationParseIsoFormat(value, index + 1)
    } else if (strictIso) {
        return null
    } else if (durationIsInfinityLiteral(value, index)) {
        parsed = Long.MAX_VALUE
    } else {
        parsed = durationParseDefaultFormat(value, index, hasSign)
    }
    if (parsed == null) return null
    return if (isNegative) ((-(parsed shr 1)) shl 1) + (parsed and 1L) else parsed
}
