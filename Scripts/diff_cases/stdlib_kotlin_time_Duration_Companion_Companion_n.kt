import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.microseconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.seconds

@OptIn(kotlin.time.ExperimentalTime::class)
fun main() {
    val values = listOf(
        1.nanoseconds, 1L.nanoseconds, 1.5.nanoseconds,
        1.microseconds, 1L.microseconds, 1.5.microseconds,
        1.milliseconds, 1L.milliseconds, 1.5.milliseconds,
        1.seconds, 1L.seconds, 1.5.seconds,
        1.minutes, 1L.minutes, 1.5.minutes,
        1.hours, 1L.hours, 1.5.hours,
        1.days, 1L.days, 1.5.days,
    )

    println(values.size)
    println(Duration.Companion.convert(1.5, DurationUnit.SECONDS, DurationUnit.MILLISECONDS))
}
