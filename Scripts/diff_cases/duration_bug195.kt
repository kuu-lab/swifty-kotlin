import java.util.concurrent.TimeUnit
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.toDuration
import kotlin.time.toDurationUnit
import kotlin.time.toTimeUnit

fun main() {
    println(2.toDuration(DurationUnit.SECONDS).inWholeSeconds)
    println(1500L.toDuration(DurationUnit.MILLISECONDS).inWholeMilliseconds)
    println(1.5.toDuration(DurationUnit.MINUTES).inWholeSeconds)
    println(DurationUnit.SECONDS.toTimeUnit() == TimeUnit.SECONDS)
    println(TimeUnit.MINUTES.toDurationUnit() == DurationUnit.MINUTES)
    println(2.toDuration(DurationUnit.SECONDS).toComponents { seconds, nanos -> "$seconds/$nanos" })
}
