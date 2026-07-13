// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
import kotlin.time.*

fun main() {
    val measured = measureTimedValue {
        40 + 2
    }
    println(measured.value)
    println(measured.duration.isPositive())

    val negative = (-5).seconds
    println(negative.inWholeSeconds)
    println(negative.isNegative())

    val epoch = Instant.fromEpochMilliseconds(0)
    val later = epoch + 1500.milliseconds
    println(later.epochSeconds)
    println(later.nanosecondsOfSecond)

    val earlier = later - 2.seconds
    println(earlier.epochSeconds)
    println(earlier.nanosecondsOfSecond)
}
