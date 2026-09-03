import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val mark = TimeSource.Monotonic.markNow()
    val copy = mark + Duration.ZERO
    val comparable: ComparableTimeMark = copy
    val foreign: ComparableTimeMark = TestTimeSource().markNow()
    var rejected = false
    try {
        mark.minus(foreign)
    } catch (_: IllegalArgumentException) {
        rejected = true
    }

    println(mark == copy)
    println(mark.hashCode() == copy.hashCode())
    println(mark.toString().startsWith("ValueTimeMark(reading="))
    println(mark.hasPassedNow())
    println(mark.hasNotPassedNow())
    println(mark.minus(comparable).inWholeNanoseconds == 0L)
    println(rejected)
}
