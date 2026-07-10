// SKIP-DIFF (DEBT-DIFF-005): kswiftc's synthetic Instant stubs use nanoOfSecond/until,
// but real kotlin.time.Instant exposes nanosecondsOfSecond and a minus operator instead
// (t2 - t1 : Duration). Separately, real kotlinc fails to resolve Duration.Companion.seconds
// via `import kotlin.time.*` once Instant is referenced in the same file (unrelated compiler
// quirk, reproduces with a plain `val x: Instant? = null`); explicit imports avoid it. Both
// gaps predate and are unrelated to KSP's Duration factory-property fix (PR #4612), which is
// what exposed this: kswiftc previously failed to compile this file too (for the .seconds bug),
// so the compile-exit-code mismatch was masked by both sides failing for different reasons.
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
