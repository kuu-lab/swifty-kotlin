import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimedValue

fun main() {
    val nullable: TimedValue<String?> = TimedValue(null, 1.seconds)
    val inferred: TimedValue<String> = TimedValue("value", 1.seconds)
    println(nullable !== null)
    println(inferred !== null)
}
