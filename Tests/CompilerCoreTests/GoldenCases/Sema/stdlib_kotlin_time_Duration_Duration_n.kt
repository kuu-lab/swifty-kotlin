import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Duration.Companion.milliseconds

// KUU-1597 Sema owner: pin Duration arithmetic, conversion overloads, and toComponents callback arities; formatted values stay in Scripts/diff_cases/stdlib_kotlin_time_Duration_Duration_n.kt.
fun main() {
    val duration: Duration = 1_500.milliseconds
    val scaled: Duration = duration * 1.5
    val divided: Duration = duration / 2.0
    val seconds: Long = duration.toComponents { wholeSeconds: Long, nanos: Int ->
        wholeSeconds * 1_000_000_000L + nanos
    }
    val minutes: Long = duration.toComponents { wholeMinutes: Long, wholeSeconds: Int, nanos: Int ->
        wholeMinutes * 60L + wholeSeconds + nanos / 1_000_000_000L
    }
    val hours: Long = duration.toComponents { wholeHours: Long, wholeMinutes: Int, wholeSeconds: Int, nanos: Int ->
        wholeHours * 3_600L + wholeMinutes * 60L + wholeSeconds + nanos / 1_000_000_000L
    }
    val days: Long = duration.toComponents { wholeDays: Long, wholeHours: Int, wholeMinutes: Int, wholeSeconds: Int, nanos: Int ->
        wholeDays * 86_400L + wholeHours * 3_600L + wholeMinutes * 60L + wholeSeconds + nanos / 1_000_000_000L
    }
    val secondsAsDouble: Double = scaled.toDouble(DurationUnit.SECONDS)
    val millisecondsAsLong: Long = divided.toLong(DurationUnit.MILLISECONDS)
    val secondsAsInt: Int = duration.toInt(DurationUnit.SECONDS)
    val formatted: String = duration.toString(DurationUnit.SECONDS, 2)
}
