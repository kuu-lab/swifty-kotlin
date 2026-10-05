package kotlin.time

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract
import kotlin.math.roundToInt
import kotlin.math.roundToLong

// KSP-683
// Duration's public representation and pure operations are Kotlin source. The
// runtime only owns parsing and platform interop; the value class payload is the
// signed count shifted left by one, with a low-bit tag (0 = ns, 1 = ms).

@JvmInline
public value class Duration internal constructor(internal val rawValue: Long) : Comparable<Duration> {
    public val inWholeNanoseconds: Long
        get() = toLong(DurationUnit.NANOSECONDS)

    public override fun compareTo(other: Duration): Int {
        if ((rawValue < 0L) != (other.rawValue < 0L) || durationIsMillis(rawValue) == durationIsMillis(other.rawValue)) {
            return rawValue.compareTo(other.rawValue)
        }
        val result = if (durationIsMillis(rawValue)) 1 else -1
        return if (rawValue < 0L) -result else result
    }

    public override fun equals(other: Any?): Boolean {
        if (other !is Duration) return false
        val that = other as Duration
        return rawValue == that.rawValue
    }

    // Long.hashCode() of the tagged payload. `toInt()` only keeps the low
    // 32 bits, so a typed call disagreed with the boxed/Any path and broke the
    // equals/hashCode contract (KUU-645).
    public override fun hashCode(): Int = rawValue.hashCode()

    public override fun toString(): String = durationToString(rawValue)

    public companion object {
        // Companion-scope numeric extensions are part of the public kotlin.time API.
        // The package-level aliases below remain for existing source files that use
        // the short form without importing Duration.Companion.*.
        public fun convert(value: Double, sourceUnit: DurationUnit, targetUnit: DurationUnit): Double {
            val sourceScale = durationUnitScale(sourceUnit).toDouble()
            val targetScale = durationUnitScale(targetUnit).toDouble()
            return value * sourceScale / targetScale
        }

        public val Int.nanoseconds: Duration get() = toDuration(DurationUnit.NANOSECONDS)
        public val Long.nanoseconds: Duration get() = toDuration(DurationUnit.NANOSECONDS)
        public val Double.nanoseconds: Duration get() = toDuration(DurationUnit.NANOSECONDS)
        public val Int.microseconds: Duration get() = toDuration(DurationUnit.MICROSECONDS)
        public val Long.microseconds: Duration get() = toDuration(DurationUnit.MICROSECONDS)
        public val Double.microseconds: Duration get() = toDuration(DurationUnit.MICROSECONDS)
        public val Int.milliseconds: Duration get() = toDuration(DurationUnit.MILLISECONDS)
        public val Long.milliseconds: Duration get() = toDuration(DurationUnit.MILLISECONDS)
        public val Double.milliseconds: Duration get() = toDuration(DurationUnit.MILLISECONDS)
        public val Int.seconds: Duration get() = toDuration(DurationUnit.SECONDS)
        public val Long.seconds: Duration get() = toDuration(DurationUnit.SECONDS)
        public val Double.seconds: Duration get() = toDuration(DurationUnit.SECONDS)
        public val Int.minutes: Duration get() = toDuration(DurationUnit.MINUTES)
        public val Long.minutes: Duration get() = toDuration(DurationUnit.MINUTES)
        public val Double.minutes: Duration get() = toDuration(DurationUnit.MINUTES)
        public val Int.hours: Duration get() = toDuration(DurationUnit.HOURS)
        public val Long.hours: Duration get() = toDuration(DurationUnit.HOURS)
        public val Double.hours: Duration get() = toDuration(DurationUnit.HOURS)
        public val Int.days: Duration get() = toDuration(DurationUnit.DAYS)
        public val Long.days: Duration get() = toDuration(DurationUnit.DAYS)
        public val Double.days: Duration get() = toDuration(DurationUnit.DAYS)
    }
}

// Keep the legacy package-level spelling available to bundled implementation
// sources. The public Kotlin API exposes the same extensions through
// `Duration.Companion`; these aliases are a source-compatibility bridge for
// code that predates that migration.
public val Int.nanoseconds: Duration get() = toDuration(DurationUnit.NANOSECONDS)
public val Long.nanoseconds: Duration get() = toDuration(DurationUnit.NANOSECONDS)
public val Double.nanoseconds: Duration get() = toDuration(DurationUnit.NANOSECONDS)
public val Int.microseconds: Duration get() = toDuration(DurationUnit.MICROSECONDS)
public val Long.microseconds: Duration get() = toDuration(DurationUnit.MICROSECONDS)
public val Double.microseconds: Duration get() = toDuration(DurationUnit.MICROSECONDS)
public val Int.milliseconds: Duration get() = toDuration(DurationUnit.MILLISECONDS)
public val Long.milliseconds: Duration get() = toDuration(DurationUnit.MILLISECONDS)
public val Double.milliseconds: Duration get() = toDuration(DurationUnit.MILLISECONDS)
public val Int.seconds: Duration get() = toDuration(DurationUnit.SECONDS)
public val Long.seconds: Duration get() = toDuration(DurationUnit.SECONDS)
public val Double.seconds: Duration get() = toDuration(DurationUnit.SECONDS)
public val Int.minutes: Duration get() = toDuration(DurationUnit.MINUTES)
public val Long.minutes: Duration get() = toDuration(DurationUnit.MINUTES)
public val Double.minutes: Duration get() = toDuration(DurationUnit.MINUTES)
public val Int.hours: Duration get() = toDuration(DurationUnit.HOURS)
public val Long.hours: Duration get() = toDuration(DurationUnit.HOURS)
public val Double.hours: Duration get() = toDuration(DurationUnit.HOURS)
public val Int.days: Duration get() = toDuration(DurationUnit.DAYS)
public val Long.days: Duration get() = toDuration(DurationUnit.DAYS)
public val Double.days: Duration get() = toDuration(DurationUnit.DAYS)

private const val NANOS_PER_MICROSECOND: Long = 1_000L
private const val NANOS_PER_MILLISECOND: Long = 1_000_000L
private const val NANOS_PER_SECOND: Long = 1_000_000_000L
private const val NANOS_PER_MINUTE: Long = 60_000_000_000L
private const val NANOS_PER_HOUR: Long = 3_600_000_000_000L
private const val NANOS_PER_DAY: Long = 86_400_000_000_000L
private const val MAX_NANOS: Long = 4_611_686_018_426_999_999L
private const val MAX_MILLIS: Long = 4_611_686_018_427_387_903L
private const val MAX_NANOS_IN_MILLIS: Long = 4_611_686_018_426L
private const val NEGATIVE_INFINITY: Long = -9_223_372_036_854_775_805L

private fun durationValue(raw: Long): Long = raw shr 1
private fun durationIsMillis(raw: Long): Boolean = (raw and 1L) != 0L
private fun durationStorageScale(raw: Long): Long = if (durationIsMillis(raw)) NANOS_PER_MILLISECOND else 1L
private fun durationOfNanos(value: Long): Duration =
    if (value >= -MAX_NANOS && value <= MAX_NANOS) Duration(value shl 1)
    else Duration(((value / NANOS_PER_MILLISECOND) shl 1) + 1L)

private fun durationOfMillis(value: Long): Duration =
    if (value >= -MAX_NANOS_IN_MILLIS && value <= MAX_NANOS_IN_MILLIS) durationOfNanos(value * NANOS_PER_MILLISECOND)
    else Duration((value.coerceIn(-MAX_MILLIS, MAX_MILLIS) shl 1) + 1L)

private fun durationIsInfinite(value: Long): Boolean {
    return value == Long.MAX_VALUE || value == NEGATIVE_INFINITY
}

private fun saturatingAdd(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}

private fun saturatingMultiply(lhs: Long, rhs: Long): Long {
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

private fun durationUnitScale(unit: DurationUnit): Long = when (unit) {
    DurationUnit.NANOSECONDS -> 1L
    DurationUnit.MICROSECONDS -> NANOS_PER_MICROSECOND
    DurationUnit.MILLISECONDS -> NANOS_PER_MILLISECOND
    DurationUnit.SECONDS -> NANOS_PER_SECOND
    DurationUnit.MINUTES -> NANOS_PER_MINUTE
    DurationUnit.HOURS -> NANOS_PER_HOUR
    DurationUnit.DAYS -> NANOS_PER_DAY
}

private fun durationFromDouble(value: Double, scale: Long): Duration {
    require(!value.isNaN()) { "Duration value cannot be NaN." }
    val nanos = (value * scale.toDouble()).roundToLong()
    if (nanos >= -MAX_NANOS && nanos <= MAX_NANOS) return durationOfNanos(nanos)
    return durationOfMillis((value * (scale.toDouble() / NANOS_PER_MILLISECOND.toDouble())).roundToLong())
}

private fun durationUnitShortName(unit: DurationUnit): String = when (unit) {
    DurationUnit.NANOSECONDS -> "ns"
    DurationUnit.MICROSECONDS -> "us"
    DurationUnit.MILLISECONDS -> "ms"
    DurationUnit.SECONDS -> "s"
    DurationUnit.MINUTES -> "m"
    DurationUnit.HOURS -> "h"
    DurationUnit.DAYS -> "d"
}

private fun durationFormatToDecimals(value: Double, decimals: Int): String {
    if (decimals == 0) return value.roundToLong().toString()

    var factor = 1L
    var factorAsDouble = 1.0
    var index = 0
    while (index < decimals) {
        factor *= 10L
        factorAsDouble *= 10.0
        index += 1
    }

    // Fixed-point formatting is only exact while the scaled value fits in Long.
    // Very large finite values are still represented meaningfully by Double.toString.
    if (value > Long.MAX_VALUE.toDouble() / factorAsDouble ||
        value < Long.MIN_VALUE.toDouble() / factorAsDouble
    ) {
        return value.toString()
    }

    val rounded = (value * factorAsDouble).roundToLong()
    val negative = rounded < 0L
    val absolute = if (negative) -rounded else rounded
    val whole = absolute / factor
    val fraction = (absolute % factor).toString().let {
        var padded = it
        while (padded.length < decimals) padded = "0" + padded
        padded
    }
    return (if (negative) "-" else "") + whole + "." + fraction
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

private fun durationToString(value: Long): String {
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

public operator fun Duration.plus(other: Duration): Duration {
    if (isInfinite() || other.isInfinite()) {
        require(!(isInfinite() && other.isInfinite() && (rawValue < 0L) != (other.rawValue < 0L))) {
            "Summing infinite durations of different signs yields an undefined result."
        }
        return if (isInfinite()) this else other
    }
    val value = durationValue(rawValue)
    val otherValue = durationValue(other.rawValue)
    if (durationIsMillis(rawValue) == durationIsMillis(other.rawValue)) {
        val sum = value + otherValue
        return if (durationIsMillis(rawValue)) durationOfMillis(sum) else durationOfNanos(sum)
    }
    val millis = if (durationIsMillis(rawValue)) value else otherValue
    val nanos = if (durationIsMillis(rawValue)) otherValue else value
    val sumMillis = millis + nanos / NANOS_PER_MILLISECOND
    return if (sumMillis >= -MAX_NANOS_IN_MILLIS && sumMillis <= MAX_NANOS_IN_MILLIS) {
        durationOfNanos(sumMillis * NANOS_PER_MILLISECOND + nanos % NANOS_PER_MILLISECOND)
    } else durationOfMillis(sumMillis)
}

public operator fun Duration.minus(other: Duration): Duration =
    this + (-other)

public operator fun Duration.times(scale: Int): Duration {
    if (isInfinite()) {
        require(scale != 0) { "Multiplying infinite duration by zero yields an undefined result." }
        return if (scale > 0) this else -this
    }
    val value = durationValue(rawValue)
    val result = saturatingMultiply(value, scale.toLong())
    if (durationIsMillis(rawValue)) return durationOfMillis(result)
    if (result != Long.MAX_VALUE && result != Long.MIN_VALUE) return durationOfNanos(result)
    val millis = saturatingMultiply(value / NANOS_PER_MILLISECOND, scale.toLong())
    val remainder = (value % NANOS_PER_MILLISECOND) * scale.toLong() / NANOS_PER_MILLISECOND
    return durationOfMillis(saturatingAdd(millis, remainder))
}

public operator fun Duration.times(scale: Double): Duration {
    val intScale = scale.roundToInt()
    if (intScale.toDouble() == scale) return this * intScale
    val unit = if (durationIsMillis(rawValue)) DurationUnit.MILLISECONDS else DurationUnit.NANOSECONDS
    return durationFromDouble(toDouble(unit) * scale, durationUnitScale(unit))
}

public operator fun Duration.div(scale: Int): Duration {
    if (scale == 0) {
        require(rawValue != 0L) { "Dividing zero duration by zero yields an undefined result." }
        return Duration(if (rawValue < 0L) NEGATIVE_INFINITY else Long.MAX_VALUE)
    }
    if (isInfinite()) return if (scale > 0) this else -this
    val value = durationValue(rawValue)
    val result = value / scale.toLong()
    if (!durationIsMillis(rawValue)) return durationOfNanos(result)
    return if (result >= -MAX_NANOS_IN_MILLIS && result <= MAX_NANOS_IN_MILLIS) {
        durationOfNanos(result * NANOS_PER_MILLISECOND + (value % scale.toLong()) * NANOS_PER_MILLISECOND / scale.toLong())
    } else durationOfMillis(result)
}

public operator fun Duration.div(scale: Double): Duration {
    val intScale = scale.roundToInt()
    if (intScale.toDouble() == scale && intScale != 0) return this / intScale
    val unit = if (durationIsMillis(rawValue)) DurationUnit.MILLISECONDS else DurationUnit.NANOSECONDS
    return durationFromDouble(toDouble(unit) / scale, durationUnitScale(unit))
}

public operator fun Duration.div(other: Duration): Double {
    val unit = if (durationIsMillis(rawValue) || durationIsMillis(other.rawValue)) DurationUnit.MILLISECONDS else DurationUnit.NANOSECONDS
    return toDouble(unit) / other.toDouble(unit)
}

public operator fun Duration.unaryMinus(): Duration =
    Duration((-durationValue(rawValue) shl 1) + (rawValue and 1L))

public val Duration.absoluteValue: Duration
    get() = if (rawValue < 0L) -this else this

public fun Duration.isNegative(): Boolean = rawValue < 0L

public fun Duration.isPositive(): Boolean = rawValue > 0L

public fun Duration.isInfinite(): Boolean = durationIsInfinite(rawValue)

public fun Duration.isFinite(): Boolean = !this.isInfinite()

val Duration.inWholeMilliseconds: Long get() = toLong(DurationUnit.MILLISECONDS)

val Duration.inWholeMicroseconds: Long get() = toLong(DurationUnit.MICROSECONDS)

val Duration.inWholeSeconds: Long get() = toLong(DurationUnit.SECONDS)

val Duration.inWholeMinutes: Long get() = toLong(DurationUnit.MINUTES)

val Duration.inWholeHours: Long get() = toLong(DurationUnit.HOURS)

val Duration.inWholeDays: Long get() = toLong(DurationUnit.DAYS)

public val Duration.hoursComponent: Int
    get() = if (durationIsInfinite(rawValue)) 0 else (inWholeHours % 24L).toInt()

public val Duration.minutesComponent: Int
    get() = if (durationIsInfinite(rawValue)) 0 else (inWholeMinutes % 60L).toInt()

public val Duration.secondsComponent: Int
    get() = if (durationIsInfinite(rawValue)) 0 else (inWholeSeconds % 60L).toInt()

public val Duration.nanosecondsComponent: Int
    get() = if (durationIsInfinite(rawValue)) 0 else ((durationValue(rawValue) % (NANOS_PER_SECOND / durationStorageScale(rawValue))) * durationStorageScale(rawValue)).toInt()

public fun Duration.toDouble(unit: DurationUnit): Double {
    if (isInfinite()) return if (rawValue < 0L) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
    val sourceScale = durationStorageScale(rawValue)
    val targetScale = durationUnitScale(unit)
    val value = durationValue(rawValue).toDouble()
    return if (sourceScale <= targetScale) value / (targetScale / sourceScale).toDouble()
        else value * (sourceScale / targetScale).toDouble()
}

public fun Duration.toLong(unit: DurationUnit): Long {
    if (isInfinite()) return if (rawValue < 0L) Long.MIN_VALUE else Long.MAX_VALUE
    val sourceScale = durationStorageScale(rawValue)
    val targetScale = durationUnitScale(unit)
    val value = durationValue(rawValue)
    return if (sourceScale <= targetScale) value / (targetScale / sourceScale)
        else saturatingMultiply(value, sourceScale / targetScale)
}

public fun Duration.toInt(unit: DurationUnit): Int {
    val wholeValue = toLong(unit)
    return wholeValue.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
}

public fun Duration.toString(unit: DurationUnit, decimals: Int = 0): String {
    require(decimals >= 0) { "decimals must be not negative, but was $decimals" }
    val number = toDouble(unit)
    if (number.isInfinite()) return number.toString()
    return durationFormatToDecimals(number, decimals.coerceAtMost(12)) + durationUnitShortName(unit)
}

fun Duration.toIsoString(): String {
    val ns = rawValue
    if (ns == Long.MAX_VALUE) return "PT9999999999999H"
    if (ns == NEGATIVE_INFINITY) return "-PT9999999999999H"
    val isNeg = ns < 0L
    val scale = durationStorageScale(ns)
    var rem = if (isNeg) -durationValue(ns) else durationValue(ns)
    val hours = rem / (NANOS_PER_HOUR / scale)
    rem %= NANOS_PER_HOUR / scale
    val minutes = rem / (NANOS_PER_MINUTE / scale)
    rem %= NANOS_PER_MINUTE / scale
    val seconds = rem / (NANOS_PER_SECOND / scale)
    val nanos = (rem % (NANOS_PER_SECOND / scale)) * scale
    val sb = StringBuilder()
    if (isNeg) sb.append('-')
    sb.append('P')
    sb.append('T')
    if (hours != 0L) { sb.append(hours); sb.append('H') }
    if (minutes != 0L || (hours != 0L && (seconds != 0L || nanos != 0L))) {
        sb.append(minutes)
        sb.append('M')
    }
    if (seconds != 0L || nanos != 0L || (hours == 0L && minutes == 0L)) {
        sb.append(seconds)
        if (nanos != 0L) {
            sb.append('.')
            var width = 9
            var divisor = 1L
            if (nanos % 1_000_000L == 0L) {
                width = 3
                divisor = 1_000_000L
            } else if (nanos % 1_000L == 0L) {
                width = 6
                divisor = 1_000L
            }
            val fractionValue = nanos / divisor
            val frac = fractionValue.toString()
            var pad = width - frac.length
            while (pad > 0) { sb.append('0'); pad -= 1 }
            var i = 0
            while (i < frac.length) { sb.append(frac[i]); i += 1 }
        }
        sb.append('S')
    }
    return sb.toString()
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> Duration.toComponents(action: (Long, Int) -> T): T {
    contract { callsInPlace(action, InvocationKind.EXACTLY_ONCE) }
    return action(inWholeSeconds, nanosecondsComponent)
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> Duration.toComponents(action: (Long, Int, Int) -> T): T {
    contract { callsInPlace(action, InvocationKind.EXACTLY_ONCE) }
    return action(inWholeMinutes, secondsComponent, nanosecondsComponent)
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> Duration.toComponents(action: (Long, Int, Int, Int) -> T): T {
    contract { callsInPlace(action, InvocationKind.EXACTLY_ONCE) }
    return action(inWholeHours, minutesComponent, secondsComponent, nanosecondsComponent)
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> Duration.toComponents(action: (Long, Int, Int, Int, Int) -> T): T {
    contract { callsInPlace(action, InvocationKind.EXACTLY_ONCE) }
    return action(inWholeDays, hoursComponent, minutesComponent, secondsComponent, nanosecondsComponent)
}

public fun Int.toDuration(unit: DurationUnit): Duration =
    toLong().toDuration(unit)

public fun Long.toDuration(unit: DurationUnit): Duration {
    val scale = durationUnitScale(unit)
    val maxNanosInUnit = MAX_NANOS / scale
    if (this >= -maxNanosInUnit && this <= maxNanosInUnit) return durationOfNanos(this * scale)
    val millis = if (scale < NANOS_PER_MILLISECOND) this / (NANOS_PER_MILLISECOND / scale)
        else saturatingMultiply(this, scale / NANOS_PER_MILLISECOND)
    return durationOfMillis(millis)
}

public fun Double.toDuration(unit: DurationUnit): Duration =
    durationFromDouble(this, durationUnitScale(unit))

// Companion-scoped constants and parsing entry points. These use the Companion
// short-form dispatch fallback (CallTypeChecker+MemberCallInferenceRegularResolution)
// so both `Duration.ZERO` and `Duration.Companion.ZERO` resolve. The __kk_duration_*
// bridges are receiver-less package-scope functions, called without `this.`.
public val Duration.Companion.ZERO: Duration get() = Duration(0L)

public val Duration.Companion.INFINITE: Duration get() = Duration(Long.MAX_VALUE)

public fun Duration.Companion.parse(value: String): Duration = Duration(__kk_duration_parse(value))

public fun Duration.Companion.parseOrNull(value: String): Duration? = __kk_duration_parseOrNull(value)?.let { Duration(it) }

public fun Duration.Companion.parseIsoString(value: String): Duration = Duration(__kk_duration_parseIsoString(value))

public fun Duration.Companion.parseIsoStringOrNull(value: String): Duration? = __kk_duration_parseIsoStringOrNull(value)?.let { Duration(it) }
