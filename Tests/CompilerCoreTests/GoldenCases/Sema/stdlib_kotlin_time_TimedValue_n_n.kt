import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimedValue

// KUU-1597 Golden-only owner: pin nullable and inferred TimedValue type arguments. The diff's two non-null booleans duplicate construction already executed by stdlib_kotlin_time_Monotonic_n.kt and stdlib_kotlin_time_n_n.kt.
fun main() {
    val nullable: TimedValue<String?> = TimedValue(null, 1.seconds)
    val inferred: TimedValue<String> = TimedValue("value", 1.seconds)
}
