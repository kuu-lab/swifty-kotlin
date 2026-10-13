import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource
import kotlin.time.TimedValue
import kotlin.time.measureTime
import kotlin.time.measureTimedValue

// KUU-1597 Sema owner: pin measureTime/measureTimedValue receiver and result types; callback and value behavior stays in Scripts/diff_cases/stdlib_kotlin_time_Monotonic_n.kt.
@OptIn(ExperimentalTime::class)
fun main() {
    val elapsed: Duration = TimeSource.Monotonic.measureTime {}
    val timed: TimedValue<String> = TimeSource.Monotonic.measureTimedValue { "value" }
}
