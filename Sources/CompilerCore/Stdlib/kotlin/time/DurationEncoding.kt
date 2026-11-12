package kotlin.time

import kotlin.math.roundToLong

internal const val NANOS_PER_MICROSECOND: Long = 1_000L
internal const val NANOS_PER_MILLISECOND: Long = 1_000_000L
internal const val NANOS_PER_SECOND: Long = 1_000_000_000L
internal const val NANOS_PER_MINUTE: Long = 60_000_000_000L
internal const val NANOS_PER_HOUR: Long = 3_600_000_000_000L
internal const val NANOS_PER_DAY: Long = 86_400_000_000_000L
internal const val MAX_NANOS: Long = 4_611_686_018_426_999_999L
internal const val MAX_MILLIS: Long = 4_611_686_018_427_387_903L
internal const val MAX_NANOS_IN_MILLIS: Long = 4_611_686_018_426L
internal const val NEGATIVE_INFINITY: Long = -9_223_372_036_854_775_805L

internal fun durationValue(raw: Long): Long = raw shr 1
internal fun durationIsMillis(raw: Long): Boolean = (raw and 1L) != 0L
internal fun durationStorageScale(raw: Long): Long = if (durationIsMillis(raw)) NANOS_PER_MILLISECOND else 1L

internal fun durationIsInfinite(value: Long): Boolean {
    return value == Long.MAX_VALUE || value == NEGATIVE_INFINITY
}

internal fun saturatingMultiply(lhs: Long, rhs: Long): Long {
    if (lhs == 0L || rhs == 0L) return 0L
    if (lhs == Long.MIN_VALUE && rhs == -1L) return Long.MAX_VALUE
    if (rhs == Long.MIN_VALUE && lhs == -1L) return Long.MAX_VALUE
    if (lhs > 0L) {
        if (rhs > 0L && lhs > Long.MAX_VALUE / rhs) return Long.MAX_VALUE
        if (rhs < 0L && rhs < Long.MIN_VALUE / lhs) return Long.MIN_VALUE
    } else {
        if (rhs > 0L && lhs < Long.MIN_VALUE / rhs) return Long.MIN_VALUE
        if (rhs < 0L && lhs < Long.MAX_VALUE / rhs) return Long.MAX_VALUE
    }
    return lhs * rhs
}

internal fun durationUnitScale(unit: DurationUnit): Long = when (unit) {
    DurationUnit.NANOSECONDS -> 1L
    DurationUnit.MICROSECONDS -> NANOS_PER_MICROSECOND
    DurationUnit.MILLISECONDS -> NANOS_PER_MILLISECOND
    DurationUnit.SECONDS -> NANOS_PER_SECOND
    DurationUnit.MINUTES -> NANOS_PER_MINUTE
    DurationUnit.HOURS -> NANOS_PER_HOUR
    DurationUnit.DAYS -> NANOS_PER_DAY
}

private fun durationFraction(value: Long, width: Int): String {
    var result = value.toString()
    while (result.length < width) result = "0" + result
    while (result.endsWith("0")) result = result.substring(0, result.length - 1)
    if (result.length >= 3) {
        while (result.length % 3 != 0) result += "0"
    }
    return result
}

internal fun durationToString(value: Long): String {
    if (value == Long.MAX_VALUE) return "Infinity"
    if (value == NEGATIVE_INFINITY) return "-Infinity"
    if (value == 0L) return "0s"

    val negative = value < 0L
    val scale = durationStorageScale(value)
    var remaining = if (negative) -durationValue(value) else durationValue(value)
    val days = remaining / (NANOS_PER_DAY / scale)
    remaining %= NANOS_PER_DAY / scale
    val hours = remaining / (NANOS_PER_HOUR / scale)
    remaining %= NANOS_PER_HOUR / scale
    val minutes = remaining / (NANOS_PER_MINUTE / scale)
    remaining %= NANOS_PER_MINUTE / scale
    val seconds = remaining / (NANOS_PER_SECOND / scale)
    val nanos = (remaining % (NANOS_PER_SECOND / scale)) * scale

    val parts = StringBuilder()
    var count = 0
    if (days != 0L) { parts.append(days); parts.append('d'); count += 1 }
    if (hours != 0L || (days != 0L && (minutes != 0L || seconds != 0L || nanos != 0L))) {
        if (count > 0) parts.append(' ')
        parts.append(hours); parts.append('h'); count += 1
    }
    if (minutes != 0L || ((hours != 0L || days != 0L) && (seconds != 0L || nanos != 0L))) {
        if (count > 0) parts.append(' ')
        parts.append(minutes); parts.append('m'); count += 1
    }
    if (seconds != 0L || nanos != 0L) {
        if (count > 0) parts.append(' ')
        if (seconds != 0L || days != 0L || hours != 0L || minutes != 0L) {
            parts.append(seconds)
            if (nanos != 0L) {
                parts.append('.')
                val width = if (nanos % NANOS_PER_MILLISECOND == 0L) 3
                    else if (nanos % NANOS_PER_MICROSECOND == 0L) 6 else 9
                parts.append(durationFraction(nanos, width))
            }
            parts.append('s')
        } else if (nanos >= NANOS_PER_MILLISECOND) {
            parts.append(nanos / NANOS_PER_MILLISECOND)
            val remainder = nanos % NANOS_PER_MILLISECOND
            if (remainder != 0L) {
                parts.append('.')
                parts.append(durationFraction(remainder, 6))
            }
            parts.append("ms")
        } else if (nanos >= NANOS_PER_MICROSECOND) {
            parts.append(nanos / NANOS_PER_MICROSECOND)
            val remainder = nanos % NANOS_PER_MICROSECOND
            if (remainder != 0L) {
                parts.append('.')
                parts.append(durationFraction(remainder, 3))
            }
            parts.append("us")
        } else {
            parts.append(nanos); parts.append("ns")
        }
        count += 1
    }

    val body = parts.toString()
    return if (!negative) body else if (count > 1) "-($body)" else "-$body"
}

internal fun durationRawOfNanos(value: Long): Long =
    if (value >= -MAX_NANOS && value <= MAX_NANOS) value shl 1
    else ((value / NANOS_PER_MILLISECOND) shl 1) + 1L

internal fun durationRawOfMillis(value: Long): Long =
    if (value >= -MAX_NANOS_IN_MILLIS && value <= MAX_NANOS_IN_MILLIS) durationRawOfNanos(value * NANOS_PER_MILLISECOND)
    else (value.coerceIn(-MAX_MILLIS, MAX_MILLIS) shl 1) + 1L

internal fun addDurationRaw(raw: Long, other: Long): Long {
    val infinite = durationIsInfinite(raw)
    val otherInfinite = durationIsInfinite(other)
    if (infinite || otherInfinite) {
        require(!(infinite && otherInfinite && (raw < 0L) != (other < 0L))) {
            "Summing infinite durations of different signs yields an undefined result."
        }
        return if (infinite) raw else other
    }
    val left = durationValue(raw)
    val right = durationValue(other)
    val leftMillis = durationIsMillis(raw)
    if (leftMillis == durationIsMillis(other)) {
        val sum = left + right
        return if (leftMillis) durationRawOfMillis(sum) else durationRawOfNanos(sum)
    }
    val millis = if (leftMillis) left else right
    val nanos = if (leftMillis) right else left
    val sumMillis = millis + nanos / NANOS_PER_MILLISECOND
    return if (sumMillis >= -MAX_NANOS_IN_MILLIS && sumMillis <= MAX_NANOS_IN_MILLIS) {
        durationRawOfNanos(sumMillis * NANOS_PER_MILLISECOND + nanos % NANOS_PER_MILLISECOND)
    } else durationRawOfMillis(sumMillis)
}

internal fun durationRawFromDouble(value: Double, scale: Long): Long {
    require(!value.isNaN()) { "Duration value cannot be NaN." }
    val nanos = (value * scale.toDouble()).roundToLong()
    if (nanos >= -MAX_NANOS && nanos <= MAX_NANOS) return durationRawOfNanos(nanos)
    return durationRawOfMillis((value * (scale.toDouble() / NANOS_PER_MILLISECOND.toDouble())).roundToLong())
}

internal fun durationRawFromLong(value: Long, unit: DurationUnit): Long {
    val scale = durationUnitScale(unit)
    val maxNanosInUnit = MAX_NANOS / scale
    if (value >= -maxNanosInUnit && value <= maxNanosInUnit) return durationRawOfNanos(value * scale)
    val millis = if (scale < NANOS_PER_MILLISECOND) value / (NANOS_PER_MILLISECOND / scale)
        else saturatingMultiply(value, scale / NANOS_PER_MILLISECOND)
    return durationRawOfMillis(millis)
}

internal fun durationRawToDouble(rawValue: Long, unit: DurationUnit): Double {
    if (durationIsInfinite(rawValue)) return if (rawValue < 0L) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
    val sourceScale = durationStorageScale(rawValue)
    val targetScale = durationUnitScale(unit)
    val value = durationValue(rawValue).toDouble()
    return if (sourceScale <= targetScale) value / (targetScale / sourceScale).toDouble()
        else value * (sourceScale / targetScale).toDouble()
}

internal fun durationRawToLong(rawValue: Long, unit: DurationUnit): Long {
    if (durationIsInfinite(rawValue)) return if (rawValue < 0L) Long.MIN_VALUE else Long.MAX_VALUE
    val sourceScale = durationStorageScale(rawValue)
    val targetScale = durationUnitScale(unit)
    val value = durationValue(rawValue)
    return if (sourceScale <= targetScale) value / (targetScale / sourceScale)
        else saturatingMultiply(value, sourceScale / targetScale)
}

internal fun compareDurationRaw(rawValue: Long, otherRawValue: Long): Int {
    if ((rawValue < 0L) != (otherRawValue < 0L) || durationIsMillis(rawValue) == durationIsMillis(otherRawValue)) {
        return rawValue.compareTo(otherRawValue)
    }
    val result = if (durationIsMillis(rawValue)) 1 else -1
    return if (rawValue < 0L) -result else result
}
