package kotlin.time

// Pure-Kotlin port of the Duration parsing grammar shared with the native
// runtime (RuntimeDuration.swift): an optional leading sign, then either the
// ISO-8601 form introduced by 'P', the case-insensitive literal "infinity"
// (non-strict mode only), or the default unit-suffixed component list whose
// units must appear in strictly decreasing order of magnitude.

private class DurationParseCursor(
    val value: String,
    var index: Int,
    val end: Int,
)

private class DurationParsedNumber(
    val whole: Long,
    val fraction: Double,
    val hasFraction: Boolean,
    val overflow: Boolean,
    val sign: Int,
)

private class DurationParsedUnit(
    val order: Int,
    val scale: Long,
)

private fun durationParseDigit(c: Char): Int = if (c >= '0' && c <= '9') c - '0' else -1

private fun durationParseSign(cursor: DurationParseCursor): Int {
    if (cursor.index >= cursor.end) return 1
    if (cursor.value[cursor.index] == '-') {
        cursor.index += 1
        return -1
    }
    if (cursor.value[cursor.index] == '+') {
        cursor.index += 1
        return 1
    }
    return 1
}

private fun durationParseNumber(cursor: DurationParseCursor, allowSign: Boolean): DurationParsedNumber? {
    val sign = if (allowSign) durationParseSign(cursor) else 1
    val digitsStart = cursor.index
    // Drop leading zeros so a zero-padded value is not reported as overflow.
    while (cursor.index < cursor.end && cursor.value[cursor.index] == '0') {
        cursor.index += 1
    }
    var whole = 0L
    var overflow = false
    while (cursor.index < cursor.end) {
        val digit = durationParseDigit(cursor.value[cursor.index])
        if (digit < 0) break
        if (!overflow) {
            if (whole > (Long.MAX_VALUE - digit) / 10L) {
                overflow = true
                whole = Long.MAX_VALUE
            } else {
                whole = whole * 10L + digit
            }
        }
        cursor.index += 1
    }
    if (cursor.index == digitsStart) return null

    var fraction = 0.0
    var hasFraction = false
    if (cursor.index < cursor.end && cursor.value[cursor.index] == '.') {
        cursor.index += 1
        val fractionStart = cursor.index
        var place = 10.0
        while (cursor.index < cursor.end) {
            val digit = durationParseDigit(cursor.value[cursor.index])
            if (digit < 0) break
            fraction += digit / place
            place *= 10.0
            cursor.index += 1
        }
        if (cursor.index == fractionStart) return null
        hasFraction = true
    }
    return DurationParsedNumber(whole, fraction, hasFraction, overflow, sign)
}

private fun durationParseDefaultUnit(cursor: DurationParseCursor): DurationParsedUnit? {
    val start = cursor.index
    while (cursor.index < cursor.end) {
        val c = cursor.value[cursor.index]
        if (c < 'a' || c > 'z') break
        cursor.index += 1
    }
    if (cursor.index == start) return null
    return when (cursor.value.substring(start, cursor.index)) {
        "d" -> DurationParsedUnit(6, NANOS_PER_DAY)
        "h" -> DurationParsedUnit(5, NANOS_PER_HOUR)
        "m" -> DurationParsedUnit(4, NANOS_PER_MINUTE)
        "s" -> DurationParsedUnit(3, NANOS_PER_SECOND)
        "ms" -> DurationParsedUnit(2, NANOS_PER_MILLISECOND)
        "us" -> DurationParsedUnit(1, NANOS_PER_MICROSECOND)
        "ns" -> DurationParsedUnit(0, 1L)
        else -> null
    }
}

private fun durationParseIsoUnit(c: Char, inTime: Boolean): DurationParsedUnit? {
    if (c == 'D' && !inTime) return DurationParsedUnit(6, NANOS_PER_DAY)
    if (c == 'H' && inTime) return DurationParsedUnit(5, NANOS_PER_HOUR)
    if (c == 'M' && inTime) return DurationParsedUnit(4, NANOS_PER_MINUTE)
    if (c == 'S' && inTime) return DurationParsedUnit(3, NANOS_PER_SECOND)
    return null
}

// Saturating raw addition mirroring the native runtimeDurationAdd: unlike
// addDurationRaw it never throws on opposing infinities, because parsing can
// produce saturated components of either sign within a single string.
private fun durationParseAddRaw(lhs: Long, rhs: Long): Long {
    if (durationIsInfinite(lhs)) return lhs
    if (durationIsInfinite(rhs)) return rhs
    val left = lhs shr 1
    val right = rhs shr 1
    if ((lhs and 1L) == (rhs and 1L)) {
        val sum = left + right
        return if ((lhs and 1L) == 0L) durationRawOfNanos(sum) else durationRawOfMillis(sum)
    }
    val millis = if ((lhs and 1L) == 1L) left else right
    val nanos = if ((lhs and 1L) == 0L) left else right
    val sumMillis = millis + nanos / NANOS_PER_MILLISECOND
    return if (sumMillis >= -MAX_NANOS_IN_MILLIS && sumMillis <= MAX_NANOS_IN_MILLIS) {
        durationRawOfNanos(sumMillis * NANOS_PER_MILLISECOND + nanos % NANOS_PER_MILLISECOND)
    } else {
        durationRawOfMillis(sumMillis)
    }
}

private fun durationParseNegateRaw(raw: Long): Long = ((-(raw shr 1)) shl 1) + (raw and 1L)

private fun durationRawFromLongScale(value: Long, scale: Long): Long {
    val maxNanosInUnit = MAX_NANOS / scale
    if (value >= -maxNanosInUnit && value <= maxNanosInUnit) return durationRawOfNanos(value * scale)
    val millis = if (scale < NANOS_PER_MILLISECOND) {
        value / (NANOS_PER_MILLISECOND / scale)
    } else {
        saturatingMultiply(value, scale / NANOS_PER_MILLISECOND)
    }
    return durationRawOfMillis(millis)
}

private fun durationParseComponentRaw(number: DurationParsedNumber, scale: Long): Long {
    val wholeRaw = durationRawFromLongScale(number.whole, scale)
    val fractionRaw = durationRawFromDouble(number.fraction, scale)
    val sum = durationParseAddRaw(wholeRaw, fractionRaw)
    return if (number.sign < 0) durationParseNegateRaw(sum) else sum
}

private fun durationParseIsoFormat(value: String, startIndex: Int): Long? {
    val end = value.length
    val cursor = DurationParseCursor(value, startIndex, end)
    if (cursor.index >= end) return null

    var inTime = false
    var prevOrder = 0
    var hasAny = false
    var total = 0L

    while (cursor.index < end) {
        if (value[cursor.index] == 'T') {
            if (inTime) return null
            cursor.index += 1
            if (cursor.index == end) return null
            inTime = true
            continue
        }

        val number = durationParseNumber(cursor, allowSign = true) ?: return null
        if (cursor.index >= end) return null
        if (number.hasFraction && value[cursor.index] != 'S') return null
        val unit = durationParseIsoUnit(value[cursor.index], inTime) ?: return null
        if (hasAny && prevOrder <= unit.order) return null
        prevOrder = unit.order
        hasAny = true
        cursor.index += 1

        val component = durationParseComponentRaw(number, unit.scale)
        total = durationParseAddRaw(total, component)
    }

    if (!hasAny) return null
    return total
}

private fun durationParseDefaultFormat(value: String, startIndex: Int, hasSign: Boolean): Long? {
    val end = value.length
    var index = startIndex
    var endIndex = end
    var allowSpaces = !hasSign

    if (hasSign && index < endIndex && value[index] == '(' && value[endIndex - 1] == ')') {
        allowSpaces = true
        index += 1
        endIndex -= 1
        if (index >= endIndex) return null
    }

    val cursor = DurationParseCursor(value, index, endIndex)
    var total = 0L
    var prevOrder = 0
    var hasAny = false

    while (cursor.index < endIndex) {
        if (allowSpaces && hasAny) {
            while (cursor.index < endIndex && value[cursor.index] == ' ') {
                cursor.index += 1
            }
        }

        val number = durationParseNumber(cursor, allowSign = false) ?: return null
        if (number.overflow || cursor.index >= endIndex) return null
        val unit = durationParseDefaultUnit(cursor) ?: return null
        if (hasAny && prevOrder <= unit.order) return null
        prevOrder = unit.order
        hasAny = true

        if (number.hasFraction && cursor.index < endIndex) return null

        val component = durationParseComponentRaw(number, unit.scale)
        total = durationParseAddRaw(total, component)
    }

    return total
}

internal fun durationParseRawOrNull(value: String, strictIso: Boolean): Long? {
    if (value.isEmpty()) return null
    val end = value.length
    var index = 0
    var negative = false
    if (value[index] == '-') {
        index += 1
        negative = true
    } else if (value[index] == '+') {
        index += 1
    }
    val hasSign = index > 0
    if (index >= end) return null

    val parsed: Long?
    if (value[index] == 'P') {
        parsed = durationParseIsoFormat(value, index + 1)
    } else if (strictIso) {
        return null
    } else if (value.substring(index).lowercase() == "infinity") {
        parsed = Long.MAX_VALUE
    } else {
        parsed = durationParseDefaultFormat(value, index, hasSign)
    }
    if (parsed == null) return null
    return if (negative) durationParseNegateRaw(parsed) else parsed
}
