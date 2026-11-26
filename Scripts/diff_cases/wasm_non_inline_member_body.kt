// DIFF_WASM
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class)
fun main() {
    println(Duration.convert(1.0, DurationUnit.SECONDS, DurationUnit.MILLISECONDS))
}
