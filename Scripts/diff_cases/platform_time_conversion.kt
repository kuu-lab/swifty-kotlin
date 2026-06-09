import java.time.Duration as JavaDuration
import java.time.Instant as JavaInstant
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.DurationUnit
import kotlin.time.Instant
import kotlin.time.toJavaDuration
import kotlin.time.toJavaInstant
import kotlin.time.toKotlinDuration
import kotlin.time.toKotlinInstant
import kotlin.time.toTimeUnit

fun timeUnitLabel(unit: DurationUnit): String = when (unit.toTimeUnit()) {
    TimeUnit.NANOSECONDS -> "ns"
    TimeUnit.MICROSECONDS -> "us"
    TimeUnit.MILLISECONDS -> "ms"
    TimeUnit.SECONDS -> "s"
    TimeUnit.MINUTES -> "min"
    TimeUnit.HOURS -> "h"
    TimeUnit.DAYS -> "d"
}

fun main() {
    val instant = Instant.fromEpochMilliseconds(1_234)
    val javaInstant: JavaInstant = instant.toJavaInstant()
    val instantRoundTrip = javaInstant.toKotlinInstant()
    println(instantRoundTrip.epochSeconds == 1L)
    println(instantRoundTrip.nanoOfSecond == 234_000_000)

    val duration = 1_500.milliseconds
    val javaDuration: JavaDuration = duration.toJavaDuration()
    val durationRoundTrip = javaDuration.toKotlinDuration()
    println(durationRoundTrip.inWholeMilliseconds == 1_500L)

    println(timeUnitLabel(DurationUnit.NANOSECONDS))
    println(timeUnitLabel(DurationUnit.SECONDS))
    println(timeUnitLabel(DurationUnit.DAYS))
    println(DurationUnit.MINUTES.toTimeUnit() == TimeUnit.MINUTES)
    println(DurationUnit.HOURS.toTimeUnit() == TimeUnit.SECONDS)
}
