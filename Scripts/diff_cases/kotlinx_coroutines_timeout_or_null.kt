import kotlinx.coroutines.*
import kotlin.time.Duration.Companion.milliseconds

// `withTimeoutOrNull` mirrors withTimeout but reports an expired deadline as
// null instead of throwing.
fun main() = runBlocking {
    println(withTimeoutOrNull(5000) { 7 })
    println(withTimeoutOrNull(5000L) { "long-deadline" })
    println(withTimeoutOrNull(5000.milliseconds) { "duration-deadline" })

    println(withTimeoutOrNull(10.milliseconds) { delay(1000); 1 })
    println(withTimeoutOrNull(10) { delay(1000); "late" })

    println("done")
}
