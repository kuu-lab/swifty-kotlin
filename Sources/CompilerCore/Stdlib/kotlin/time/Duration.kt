package kotlin.time

// KSP-683
// Duration's public representation and pure operations are Kotlin source. The
// runtime only owns parsing and platform interop; the value class payload is the
// signed nanosecond count used by those bridges.

@JvmInline
public value class Duration internal constructor(internal val rawValue: Long) {
    public val inWholeNanoseconds: Long
        get() = rawValue

    public override fun equals(other: Any?): Boolean {
        if (other !is Duration) return false
        val that = other as Duration
        return rawValue == that.rawValue
    }

    public override fun hashCode(): Int = rawValue.toInt()

    public override fun toString(): String = durationToString(rawValue)
}

private const val NANOS_PER_MICROSECOND: Long = 1_000L
private const val NANOS_PER_MILLISECOND: Long = 1_000_000L
private const val NANOS_PER_SECOND: Long = 1_000_000_000L
private const val NANOS_PER_MINUTE: Long = 60_000_000_000L
private const val NANOS_PER_HOUR: Long = 3_600_000_000_000L
private const val NANOS_PER_DAY: Long = 86_400_000_000_000L

private fun durationIsInfinite(value: Long): Boolean {
    return value == Long.MAX_VALUE || value == Long.MIN_VALUE
}

private fun saturatingAdd(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}

private fun saturatingSubtract(lhs: Long, rhs: Long): Long =
    if (rhs == Long.MIN_VALUE) {
        if (lhs >= 0L) Long.MAX_VALUE else saturatingAdd(lhs, Long.MAX_VALUE) + 1L
    } else {
        saturatingAdd(lhs, -rhs)
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
    if (value.isNaN()) return Duration(0L)
    if (value.isInfinite()) return Duration(if (value < 0.0) Long.MIN_VALUE else Long.MAX_VALUE)
    val scaled = value * scale.toDouble()
    if (scaled >= Long.MAX_VALUE.toDouble()) return Duration(Long.MAX_VALUE)
    if (scaled <= Long.MIN_VALUE.toDouble()) return Duration(Long.MIN_VALUE)
    return Duration(scaled.roundToLong())
}

private fun durationToDouble(value: Long): Double = when {
    value == Long.MAX_VALUE -> Double.POSITIVE_INFINITY
    value == Long.MIN_VALUE -> Double.NEGATIVE_INFINITY
    else -> value.toDouble()
}

private fun durationFraction(value: Long, width: Int): String {
    var result = value.toString()
    while (result.length < width) result = "0" + result
    while (result.endsWith("0")) result = result.substring(0, result.length - 1)
    return result
}

private fun durationToString(value: Long): String {
    if (value == Long.MAX_VALUE) return "Infinity"
    if (value == Long.MIN_VALUE) return "-Infinity"
    if (value == 0L) return "0s"

    val negative = value < 0L
    var remaining = if (negative) -value else value
    val days = remaining / NANOS_PER_DAY
    remaining %= NANOS_PER_DAY
    val hours = remaining / NANOS_PER_HOUR
    remaining %= NANOS_PER_HOUR
    val minutes = remaining / NANOS_PER_MINUTE
    remaining %= NANOS_PER_MINUTE
    val seconds = remaining / NANOS_PER_SECOND
    val nanos = remaining % NANOS_PER_SECOND

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

public operator fun Duration.plus(other: Duration): Duration =
    Duration(saturatingAdd(rawValue, other.rawValue))

public operator fun Duration.minus(other: Duration): Duration =
    Duration(saturatingSubtract(rawValue, other.rawValue))

public operator fun Duration.times(scale: Int): Duration =
    Duration(saturatingMultiply(rawValue, scale.toLong()))

public operator fun Duration.div(scale: Int): Duration =
    if (scale == 0) {
        Duration(if (rawValue < 0L) Long.MIN_VALUE else Long.MAX_VALUE)
    } else if (rawValue == Long.MIN_VALUE && scale == -1) {
        Duration(Long.MAX_VALUE)
    } else {
        Duration(rawValue / scale.toLong())
    }

public operator fun Duration.div(other: Duration): Double =
    durationToDouble(rawValue) / durationToDouble(other.rawValue)

public operator fun Duration.unaryMinus(): Duration =
    Duration(when (rawValue) {
        Long.MIN_VALUE -> Long.MAX_VALUE
        Long.MAX_VALUE -> Long.MIN_VALUE
        else -> -rawValue
    })

public operator fun Duration.compareTo(other: Duration): Int =
    rawValue.compareTo(other.rawValue)

public val Duration.absoluteValue: Duration
    get() = Duration(if (rawValue < 0L) -rawValue else rawValue)

public fun Duration.isNegative(): Boolean = rawValue < 0L && rawValue != Long.MIN_VALUE

public fun Duration.isPositive(): Boolean = rawValue > 0L && rawValue != Long.MAX_VALUE

public fun Duration.isInfinite(): Boolean = durationIsInfinite(rawValue)

public fun Duration.isFinite(): Boolean = !this.isInfinite()

val Duration.inWholeMilliseconds: Long get() = rawValue / NANOS_PER_MILLISECOND

val Duration.inWholeMicroseconds: Long get() = rawValue / NANOS_PER_MICROSECOND

val Duration.inWholeSeconds: Long get() = rawValue / NANOS_PER_SECOND

val Duration.inWholeMinutes: Long get() = rawValue / NANOS_PER_MINUTE

val Duration.inWholeHours: Long get() = rawValue / NANOS_PER_HOUR

val Duration.inWholeDays: Long get() = rawValue / NANOS_PER_DAY

fun Duration.toIsoString(): String {
    val ns = rawValue
    if (ns == Long.MAX_VALUE) return "PT9999999999999H"
    if (ns == Long.MIN_VALUE) return "-PT9999999999999H"
    val isNeg = ns < 0L
    var rem = if (isNeg) -ns else ns
    val hours = rem / 3_600_000_000_000L
    rem %= 3_600_000_000_000L
    val minutes = rem / 60_000_000_000L
    rem %= 60_000_000_000L
    val seconds = rem / 1_000_000_000L
    val nanos = rem % 1_000_000_000L
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

fun <T> Duration.toComponents(action: (Long, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0)
    }
    val s = totalNs / 1_000_000_000L
    val n = (totalNs % 1_000_000_000L).toInt()
    return action(s, n)
}

fun <T> Duration.toComponents(action: (Long, Int, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0, 0)
    }
    var rem = totalNs
    val m = rem / 60_000_000_000L
    rem %= 60_000_000_000L
    val s = (rem / 1_000_000_000L).toInt()
    val n = (rem % 1_000_000_000L).toInt()
    return action(m, s, n)
}

fun <T> Duration.toComponents(action: (Long, Int, Int, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0, 0, 0)
    }
    var rem = totalNs
    val h = rem / 3_600_000_000_000L
    rem %= 3_600_000_000_000L
    val m = (rem / 60_000_000_000L).toInt()
    rem %= 60_000_000_000L
    val s = (rem / 1_000_000_000L).toInt()
    val n = (rem % 1_000_000_000L).toInt()
    return action(h, m, s, n)
}

fun <T> Duration.toComponents(action: (Long, Int, Int, Int, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0, 0, 0, 0)
    }
    var rem = totalNs
    val d = rem / 86_400_000_000_000L
    rem %= 86_400_000_000_000L
    val h = (rem / 3_600_000_000_000L).toInt()
    rem %= 3_600_000_000_000L
    val m = (rem / 60_000_000_000L).toInt()
    rem %= 60_000_000_000L
    val s = (rem / 1_000_000_000L).toInt()
    val n = (rem % 1_000_000_000L).toInt()
    return action(d, h, m, s, n)
}

public fun Int.toDuration(unit: DurationUnit): Duration =
    Duration(saturatingMultiply(toLong(), durationUnitScale(unit)))

public fun Long.toDuration(unit: DurationUnit): Duration =
    Duration(saturatingMultiply(this, durationUnitScale(unit)))

public fun Double.toDuration(unit: DurationUnit): Duration =
    durationFromDouble(this, durationUnitScale(unit))

// Duration factory extension properties (Int/Long/Double receivers).
// Not Companion-scoped: the receiver is a numeric value, not the Duration class
// name, so an ordinary top-level extension property resolves correctly without
// needing Companion short-form dispatch.
public val Int.nanoseconds: Duration get() = this.toDuration(DurationUnit.NANOSECONDS)
public val Int.microseconds: Duration get() = this.toDuration(DurationUnit.MICROSECONDS)
public val Int.milliseconds: Duration get() = this.toDuration(DurationUnit.MILLISECONDS)
public val Int.seconds: Duration get() = this.toDuration(DurationUnit.SECONDS)
public val Int.minutes: Duration get() = this.toDuration(DurationUnit.MINUTES)
public val Int.hours: Duration get() = this.toDuration(DurationUnit.HOURS)
public val Int.days: Duration get() = this.toDuration(DurationUnit.DAYS)

public val Long.nanoseconds: Duration get() = this.toDuration(DurationUnit.NANOSECONDS)
public val Long.microseconds: Duration get() = this.toDuration(DurationUnit.MICROSECONDS)
public val Long.milliseconds: Duration get() = this.toDuration(DurationUnit.MILLISECONDS)
public val Long.seconds: Duration get() = this.toDuration(DurationUnit.SECONDS)
public val Long.minutes: Duration get() = this.toDuration(DurationUnit.MINUTES)
public val Long.hours: Duration get() = this.toDuration(DurationUnit.HOURS)
public val Long.days: Duration get() = this.toDuration(DurationUnit.DAYS)

public val Double.nanoseconds: Duration get() = this.toDuration(DurationUnit.NANOSECONDS)
public val Double.microseconds: Duration get() = this.toDuration(DurationUnit.MICROSECONDS)
public val Double.milliseconds: Duration get() = this.toDuration(DurationUnit.MILLISECONDS)
public val Double.seconds: Duration get() = this.toDuration(DurationUnit.SECONDS)
public val Double.minutes: Duration get() = this.toDuration(DurationUnit.MINUTES)
public val Double.hours: Duration get() = this.toDuration(DurationUnit.HOURS)
public val Double.days: Duration get() = this.toDuration(DurationUnit.DAYS)

// Companion-scoped constants and parsing entry points. These use the Companion
// short-form dispatch fallback (CallTypeChecker+MemberCallInferenceRegularResolution)
// so both `Duration.ZERO` and `Duration.Companion.ZERO` resolve. The __kk_duration_*
// bridges are receiver-less package-scope functions, called without `this.`.
public val Duration.Companion.ZERO: Duration get() = Duration(0L)

public val Duration.Companion.INFINITE: Duration get() = Duration(Long.MAX_VALUE)

public fun Duration.Companion.parse(value: String): Duration = __kk_duration_parse(value)

public fun Duration.Companion.parseOrNull(value: String): Duration? = __kk_duration_parseOrNull(value)

public fun Duration.Companion.parseIsoString(value: String): Duration = __kk_duration_parseIsoString(value)

public fun Duration.Companion.parseIsoStringOrNull(value: String): Duration? = __kk_duration_parseIsoStringOrNull(value)
