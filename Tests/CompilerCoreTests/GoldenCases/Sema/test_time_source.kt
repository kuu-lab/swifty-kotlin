import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.ComparableTimeMark
import kotlin.time.ExperimentalTime
import kotlin.time.TestTimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val source = TestTimeSource()
    val mark1 = source.markNow()
    source += 5.milliseconds
    val mark2 = source.markNow()
    println((mark2 - mark1).inWholeMilliseconds)
}
