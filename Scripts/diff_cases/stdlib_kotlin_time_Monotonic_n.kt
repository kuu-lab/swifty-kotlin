import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource
import kotlin.time.TimedValue
import kotlin.time.measureTime
import kotlin.time.measureTimedValue

@OptIn(ExperimentalTime::class)
fun main() {
    var calls = 0
    val elapsed: Duration = TimeSource.Monotonic.measureTime {
        calls += 1
    }
    val timed: TimedValue<String> = TimeSource.Monotonic.measureTimedValue {
        "value"
    }

    println(calls == 1)
    println(elapsed.inWholeNanoseconds >= 0L)
    println(timed.value)
}
