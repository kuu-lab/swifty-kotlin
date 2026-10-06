import kotlinx.coroutines.*
import kotlin.time.Duration.Companion.milliseconds

// KUU-1337: erasing a timed-out Unit result must preserve null.
fun main() = runBlocking {
    println(withTimeoutOrNull(1) { delay(5000) })
    println(withTimeoutOrNull(1L) { delay(5000) })
    println(withTimeoutOrNull(1.milliseconds) { delay(5000) })
    println(withTimeoutOrNull(0) { Unit })
    println(withTimeoutOrNull(-1L) { Unit })
    val expired = withTimeoutOrNull(1) { delay(5000) }
    println(expired == null)
    val erased: Any? = expired
    println(erased)
    println("result=$expired")
    val block: suspend CoroutineScope.() -> Unit = { delay(5000) }
    println(withTimeoutOrNull(1L, block))
    println(withTimeoutOrNull(5000) { Unit })
    println(withTimeoutOrNull(5000L) { delay(1) })
    println(withTimeoutOrNull(5000.milliseconds) { Unit })
    println(withTimeoutOrNull(1) { delay(5000); "late" })
    try {
        withTimeout(1) { delay(5000) }
    } catch (e: TimeoutCancellationException) {
        println("timeout")
    }
}
