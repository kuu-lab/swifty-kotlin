@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.time.AbstractDoubleTimeSource
import kotlin.time.AbstractLongTimeSource
import kotlin.time.Clock
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime
import kotlin.time.Instant
import kotlin.time.TimeMark
import kotlin.time.TimeSource
import kotlin.time.TimedValue

@OptIn(ExperimentalTime::class)
private class DoubleProbe : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Double = 1.0
}

@OptIn(ExperimentalTime::class)
private class LongProbe : AbstractLongTimeSource(DurationUnit.MILLISECONDS) {
    override fun read(): Long = 1L
}

@OptIn(ExperimentalTime::class)
fun main() {
    val clock: Clock = Clock.System
    val mark: TimeMark = TimeSource.Monotonic.markNow()
    val comparable: ComparableTimeMark = LongProbe().markNow()
    val instant: Instant = Instant.fromEpochMilliseconds(0L)
    val timed: TimedValue<String> = TimedValue("value", Duration.ZERO)
    val doubleMark: ComparableTimeMark = DoubleProbe().markNow()

    println(clock === Clock.System)
    println(mark !== comparable)
    println(instant.epochSeconds == 0L)
    println(timed.value)
    println(doubleMark !== comparable)
}
