import kotlinx.coroutines.*
import kotlin.time.Duration.Companion.milliseconds

// `delay` accepts millis as Long, Int, or a kotlin.time.Duration. All three
// forms suspend the coroutine through the same timer bridge; short delays are
// used so a loaded runner cannot reorder the println calls.
fun main() = runBlocking {
    println("start")
    delay(50)
    println("after-int")
    delay(50L)
    println("after-long")
    delay(50.milliseconds)
    println("after-duration")

    // A zero/negative timeout must return immediately without suspending.
    delay(0)
    println("end")
}
