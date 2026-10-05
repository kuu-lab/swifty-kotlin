import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.nanoseconds
import kotlinx.coroutines.*

fun main() = runBlocking {
    delay(1.milliseconds)
    println("delay")
    println(withTimeout(Long.MAX_VALUE.nanoseconds) { 42 })
    println(withTimeout(10_000_000_000_000L.milliseconds) { "millis" })
    println(withTimeoutOrNull(Duration.INFINITE) { "infinite" })
    println(withTimeoutOrNull((-1).milliseconds) { "unreachable" })
}
