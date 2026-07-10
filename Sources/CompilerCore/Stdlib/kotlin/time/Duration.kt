package kotlin.time

// MIGRATION-TIME-001 / KSP-471
// Duration arithmetic, predicates, component/string conversion, and factory surface.
// Migration source: Sources/Runtime/RuntimeDuration.swift
//
// All operations delegate to __kk_duration_* bridges backed by kk_* ABI functions.
// Bridge stubs are registered in HeaderHelpers+SyntheticDurationStubs.swift.
//
// Native bridges that remain (base primitives / complex logic that stays in Swift):
//   kk_duration_inWholeNanoseconds  (accesses Swift object internals)
//   kk_duration_toString            (Any.toString() is a class member and takes precedence
//                                    over extension functions; stays native)
//   kk_duration_parse*              (complex parsing logic, stays native — invoked via bridges)
//   kk_duration_toDuration_*, kk_duration_zero/infinite, kk_duration_from_nanoseconds
//                                    (internal Int64-nanosecond construction, stays native;
//                                     from_nanoseconds is also the measureTime epilogue callee)

public operator fun Duration.plus(other: Duration): Duration =
    this.__kk_duration_plus(other)

public operator fun Duration.minus(other: Duration): Duration =
    this.__kk_duration_minus(other)

public operator fun Duration.times(scale: Int): Duration =
    this.__kk_duration_times_int(scale)

public operator fun Duration.div(scale: Int): Duration =
    this.__kk_duration_div_int(scale)

public operator fun Duration.div(other: Duration): Double =
    this.__kk_duration_div_duration(other)

public operator fun Duration.unaryMinus(): Duration =
    this.__kk_duration_unary_minus()

public operator fun Duration.compareTo(other: Duration): Int =
    this.__kk_duration_compareTo(other)

public val Duration.absoluteValue: Duration
    get() = this.__kk_duration_absoluteValue()

public fun Duration.isNegative(): Boolean = this.__kk_duration_isNegative()

public fun Duration.isPositive(): Boolean = this.__kk_duration_isPositive()

public fun Duration.isInfinite(): Boolean = this.__kk_duration_isInfinite()

public fun Duration.isFinite(): Boolean = !this.isInfinite()

val Duration.inWholeMilliseconds: Long get() = inWholeNanoseconds / 1_000_000L

val Duration.inWholeMicroseconds: Long get() = inWholeNanoseconds / 1_000L

val Duration.inWholeSeconds: Long get() = inWholeNanoseconds / 1_000_000_000L

val Duration.inWholeMinutes: Long get() = inWholeNanoseconds / 60_000_000_000L

val Duration.inWholeHours: Long get() = inWholeNanoseconds / 3_600_000_000_000L

val Duration.inWholeDays: Long get() = inWholeNanoseconds / 86_400_000_000_000L

fun Duration.toIsoString(): String {
    val ns = inWholeNanoseconds
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
public val Duration.Companion.ZERO: Duration get() = __kk_duration_zero()

public val Duration.Companion.INFINITE: Duration get() = __kk_duration_infinite()

public fun Duration.Companion.parse(value: String): Duration = __kk_duration_parse(value)

public fun Duration.Companion.parseOrNull(value: String): Duration? = __kk_duration_parseOrNull(value)

public fun Duration.Companion.parseIsoString(value: String): Duration = __kk_duration_parseIsoString(value)

public fun Duration.Companion.parseIsoStringOrNull(value: String): Duration? = __kk_duration_parseIsoStringOrNull(value)
