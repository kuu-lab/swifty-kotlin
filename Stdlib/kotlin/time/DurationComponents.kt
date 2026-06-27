package kotlin.time

// MIGRATION-TIME-002: Duration component and string conversion functions.
// Reference copy — the canonical source injected at compile time is
// BundledKotlinStdlib.kotlinTimeSource in Sources/CompilerCore/Driver/BundledKotlinStdlib.swift.
//
// Native bridges that remain:
//   kk_duration_inWholeNanoseconds  (base primitive — accesses Swift object internals)
//   kk_duration_toString            (Any.toString() is a class member and takes precedence
//                                    over extension functions; stays native)
//   kk_duration_parse*              (complex parsing logic, stays native)

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
