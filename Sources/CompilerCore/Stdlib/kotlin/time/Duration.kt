package kotlin.time

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract
import kotlin.internal.KsSymbolName
import kotlin.math.roundToInt

// The value class payload is the signed count shifted left by one, with a
// low-bit tag (0 = ns, 1 = ms).

@JvmInline
public value class Duration internal constructor(internal val rawValue: Long) : Comparable<Duration> {
    public val inWholeNanoseconds: Long
        get() = toLong(DurationUnit.NANOSECONDS)

    public override fun compareTo(other: Duration): Int = compareDurationRaw(rawValue, other.rawValue)

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

private fun durationOfNanos(value: Long): Duration = Duration(durationRawOfNanos(value))

private fun durationOfMillis(value: Long): Duration = Duration(durationRawOfMillis(value))

private fun saturatingAdd(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}

private fun durationFromDouble(value: Double, scale: Long): Duration = Duration(durationRawFromDouble(value, scale))

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

public fun Duration.toDouble(unit: DurationUnit): Double = durationRawToDouble(rawValue, unit)

public fun Duration.toLong(unit: DurationUnit): Long = durationRawToLong(rawValue, unit)

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

public fun Long.toDuration(unit: DurationUnit): Duration = Duration(durationRawFromLong(this, unit))

public fun Double.toDuration(unit: DurationUnit): Duration =
    durationFromDouble(this, durationUnitScale(unit))

// Companion-scoped constants and parsing entry points use the Companion
// short-form dispatch fallback (CallTypeChecker+MemberCallInferenceRegularResolution)
// so both `Duration.ZERO` and `Duration.Companion.ZERO` resolve. The __kk_duration_*
// bridges are receiver-less package-scope functions, called without `this.`.
public val Duration.Companion.ZERO: Duration get() = Duration(0L)

public val Duration.Companion.INFINITE: Duration get() = Duration(Long.MAX_VALUE)

@KsSymbolName("kk_duration_parse")
private external fun __kk_duration_parse(value: String): Long

@KsSymbolName("kk_duration_parseOrNull")
private external fun __kk_duration_parseOrNull(value: String): Long?

@KsSymbolName("kk_duration_parseIsoString")
private external fun __kk_duration_parseIsoString(value: String): Long

@KsSymbolName("kk_duration_parseIsoStringOrNull")
private external fun __kk_duration_parseIsoStringOrNull(value: String): Long?

public fun Duration.Companion.parse(value: String): Duration = Duration(__kk_duration_parse(value))

public fun Duration.Companion.parseOrNull(value: String): Duration? = __kk_duration_parseOrNull(value)?.let { Duration(it) }

public fun Duration.Companion.parseIsoString(value: String): Duration = Duration(__kk_duration_parseIsoString(value))

public fun Duration.Companion.parseIsoStringOrNull(value: String): Duration? = __kk_duration_parseIsoStringOrNull(value)?.let { Duration(it) }
