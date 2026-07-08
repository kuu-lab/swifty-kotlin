import kotlin.time.*
import kotlin.time.Duration.Companion.seconds

fun main() {
    // fromEpochMilliseconds
    val epoch = Instant.fromEpochMilliseconds(0L)

    // epochSeconds property
    val epochSec = epoch.epochSeconds
    println(epochSec)   // 0

    // Instant arithmetic: plus/minus Duration (deterministic with epoch base)
    val d = 5.seconds
    val later = epoch + d
    val earlier = epoch - d
    println(later.epochSeconds)   // 5
    println(earlier.epochSeconds) // -5

    // comparisons
    println(epoch <= epoch) // true
    println(epoch >= epoch) // true
    println(epoch == epoch) // true
    val epoch2 = Instant.fromEpochMilliseconds(0L)
    println(epoch == epoch2) // true

    // duration between two Instants, expressed via epochSeconds difference
    // (kotlin.time.Instant has no until()/minus(Instant) helper; only
    // operator plus/minus(Duration) and Comparable<Instant>)
    val t1 = Instant.fromEpochMilliseconds(1000L)
    val t2 = Instant.fromEpochMilliseconds(3000L)
    println(t2.epochSeconds - t1.epochSeconds) // 2
}
