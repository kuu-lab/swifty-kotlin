// SKIP-DIFF (DEBT-DIFF-005): kswiftc's synthetic Instant stubs use nanoOfSecond/until,
// but real kotlin.time.Instant exposes nanosecondsOfSecond and a minus operator instead
// (t2 - t1 : Duration). Separately, real kotlinc fails to resolve Duration.Companion.seconds
// via `import kotlin.time.*` once Instant is referenced in the same file (unrelated compiler
// quirk, reproduces with a plain `val x: Instant? = null`); explicit imports avoid it. Both
// gaps predate and are unrelated to KSP's Duration factory-property fix (PR #4612), which is
// what exposed this: kswiftc previously failed to compile this file too (for the .seconds bug),
// so the compile-exit-code mismatch was masked by both sides failing for different reasons.
import kotlin.time.*

fun main() {
    // fromEpochMilliseconds
    val epoch = Instant.fromEpochMilliseconds(0L)

    // epochSeconds and nanoOfSecond properties
    val epochSec = epoch.epochSeconds
    val epochNano = epoch.nanoOfSecond
    println(epochSec)   // 0
    println(epochNano)  // 0

    // Instant arithmetic: plus/minus Duration (deterministic with epoch base)
    val d = 5.seconds
    val later = epoch + d
    val earlier = epoch - d
    println(later.epochSeconds)   // 5
    println(later.nanoOfSecond)   // 0
    println(earlier.epochSeconds) // -5
    println(earlier.nanoOfSecond) // 0

    // comparisons
    println(epoch <= epoch) // true
    println(epoch >= epoch) // true
    println(epoch == epoch) // true
    val epoch2 = Instant.fromEpochMilliseconds(0L)
    println(epoch == epoch2) // true

    // until() — duration between two Instants
    val t1 = Instant.fromEpochMilliseconds(1000L)
    val t2 = Instant.fromEpochMilliseconds(3000L)
    val diff = t1.until(t2)
    println(diff.inWholeSeconds) // 2
}
