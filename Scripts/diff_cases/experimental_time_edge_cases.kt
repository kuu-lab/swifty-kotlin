import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val start = TimeSource.Monotonic.markNow()
    val future = start + 10.seconds
    val past = future - 20.seconds

    println((future - start).inWholeMilliseconds)
    println((future - past).inWholeMilliseconds)
    println(future.hasNotPassedNow())
    println(past.hasPassedNow())
}
