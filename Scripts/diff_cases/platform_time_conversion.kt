import kotlin.time.*
import kotlin.time.Duration.Companion.milliseconds

fun main() {
    val instant = Instant.fromEpochMilliseconds(1_234)
    println(instant.toEpochMilliseconds() == 1_234L)
    println(instant.epochSeconds == 1L)
    println(instant.nanosecondsOfSecond == 234_000_000)

    val duration = 1_500.milliseconds
    println(duration.toLong(DurationUnit.MILLISECONDS) == 1_500L)
    println(duration.toLong(DurationUnit.SECONDS) == 1L)
    println(duration.toDouble(DurationUnit.SECONDS) == 1.5)
}
