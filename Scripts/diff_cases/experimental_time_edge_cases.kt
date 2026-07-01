// SKIP-DIFF (DEBT-DIFF-005): timing-sensitive — kswiftc native executes in <5ms, JVM takes >5ms
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val start = TimeSource.Monotonic.markNow()
    val future = start + 5.milliseconds
    val past = future - 10.milliseconds

    println((future - start).inWholeMilliseconds)
    println((future - past).inWholeMilliseconds)
    println(future.hasNotPassedNow())
    println(past.hasPassedNow())
}
