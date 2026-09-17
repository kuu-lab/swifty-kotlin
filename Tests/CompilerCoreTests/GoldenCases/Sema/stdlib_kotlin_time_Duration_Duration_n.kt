import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Duration.Companion.milliseconds

fun main() {
    val duration = 1_500.milliseconds
    val scaled = duration * 1.5
    val divided = duration / 2.0
    val seconds = duration.toComponents { wholeSeconds: Long, nanos: Int ->
        wholeSeconds * 1_000_000_000L + nanos
    }
    val minutes = duration.toComponents { wholeMinutes: Long, wholeSeconds: Int, nanos: Int ->
        wholeMinutes * 60L + wholeSeconds + nanos / 1_000_000_000L
    }
    val hours = duration.toComponents { wholeHours: Long, wholeMinutes: Int, wholeSeconds: Int, nanos: Int ->
        wholeHours * 3_600L + wholeMinutes * 60L + wholeSeconds + nanos / 1_000_000_000L
    }
    val days = duration.toComponents { wholeDays: Long, wholeHours: Int, wholeMinutes: Int, wholeSeconds: Int, nanos: Int ->
        wholeDays * 86_400L + wholeHours * 3_600L + wholeMinutes * 60L + wholeSeconds + nanos / 1_000_000_000L
    }

    println(scaled.toDouble(DurationUnit.SECONDS))
    println(divided.toLong(DurationUnit.MILLISECONDS))
    println(duration.toInt(DurationUnit.SECONDS))
    println(duration.toString(DurationUnit.SECONDS, 2))
    println(seconds)
    println(minutes)
    println(hours)
    println(days)
}
