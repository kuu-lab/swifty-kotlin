import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

fun main() {
    // fromEpochMilliseconds
    val epoch = Instant.fromEpochMilliseconds(0L)

    // epochSeconds and nanosecondsOfSecond properties
    val epochSec = epoch.epochSeconds
    val epochNano = epoch.nanosecondsOfSecond
    println(epochSec)   // 0
    println(epochNano)  // 0

    // Instant arithmetic: plus/minus Duration (deterministic with epoch base)
    val d = 5.seconds
    val later = epoch + d
    val earlier = epoch - d
    println(later.epochSeconds)          // 5
    println(later.nanosecondsOfSecond)   // 0
    println(earlier.epochSeconds)        // -5
    println(earlier.nanosecondsOfSecond) // 0

    // comparisons
    println(epoch <= epoch) // true
    println(epoch >= epoch) // true
    println(epoch == epoch) // true
    val epoch2 = Instant.fromEpochMilliseconds(0L)
    println(epoch == epoch2) // true

    // minus(Instant) — duration between two Instants
    val t1 = Instant.fromEpochMilliseconds(1000L)
    val t2 = Instant.fromEpochMilliseconds(3000L)
    val diff = t2 - t1
    println(diff.inWholeSeconds) // 2
}
