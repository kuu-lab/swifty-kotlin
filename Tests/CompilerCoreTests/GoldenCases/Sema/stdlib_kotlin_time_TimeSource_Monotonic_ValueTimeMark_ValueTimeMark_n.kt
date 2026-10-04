import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource

@OptIn(ExperimentalTime::class)
fun valueTimeMarkProbe(): Boolean {
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
    return mark == copy &&
        mark.hashCode() == copy.hashCode() &&
        mark.toString().startsWith("ValueTimeMark(reading=") &&
        mark.hasPassedNow() &&
        !mark.hasNotPassedNow() &&
        (mark - comparable).inWholeNanoseconds == 0L &&
        rejected
}
