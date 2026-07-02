// SKIP-DIFF (DEBT-DIFF-003): advanced coroutine/channel/flow parity tracking
import kotlinx.coroutines.*

suspend fun step(value: Int): Int {
    delay(1)
    return value + 1
}

suspend fun failStep(): Int {
    delay(1)
    throw IllegalStateException("suspend-boom")
}

fun main() = runBlocking {
    val ok = step(41)
    println(ok)

    try {
        failStep()
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    val resumed = withContext(Dispatchers.Default) {
        step(9)
    }
    println(resumed)
}
