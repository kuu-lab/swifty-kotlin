import kotlin.time.Duration.Companion.microseconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.ExperimentalTime
import kotlin.time.TestTimeSource

@OptIn(ExperimentalTime::class)
fun main() {
    val source = TestTimeSource()
    val first = source.markNow()
    source += 5.milliseconds
    val second = source.markNow()
    source += (-250L).microseconds
    val third = source.markNow()

    println((second - first).inWholeMilliseconds)
    println((third - second).inWholeNanoseconds)

}
