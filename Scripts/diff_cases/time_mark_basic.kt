import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val mark = TimeSource.Monotonic.markNow()
    val future = mark + 5.seconds
    val past = mark - 5.seconds

    // elapsedNow(): a fresh mark is already (weakly) in the past.
    println(mark.elapsedNow().inWholeNanoseconds >= 0L)
    println(future.elapsedNow().inWholeMilliseconds < 0L)
    println(past.elapsedNow().inWholeSeconds >= 5L)

    // hasPassedNow() / hasNotPassedNow() are mutually exclusive.
    println(past.hasPassedNow())
    println(past.hasNotPassedNow())
    println(future.hasPassedNow())
    println(future.hasNotPassedNow())

    // Mark-to-mark differences are exact regardless of the underlying clock.
    println((future - mark).inWholeMilliseconds)
    println((past - mark).inWholeMilliseconds)
    println((future - past).inWholeSeconds)
    println((mark - mark).inWholeNanoseconds)

    // Shifting back and forth restores the original reading.
    val roundTrip = (mark + 250.milliseconds) - 250.milliseconds
    println(roundTrip.compareTo(mark))
    println(future > mark)
    println(past < mark)
    println(future >= past)
}
