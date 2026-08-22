import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.toDuration

fun main() {
    println(2.toDuration(DurationUnit.SECONDS).inWholeSeconds)
    println(1500L.toDuration(DurationUnit.MILLISECONDS).inWholeMilliseconds)
    println(1.5.toDuration(DurationUnit.MINUTES).inWholeSeconds)
    println(2.toDuration(DurationUnit.SECONDS).toComponents { seconds, nanos -> "$seconds/$nanos" })
}
