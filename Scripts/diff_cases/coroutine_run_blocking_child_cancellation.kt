import kotlinx.coroutines.*

// A child Job cancelled by its owner must not make runBlocking throw when
// the surrounding scope itself completed normally.
fun main() = runBlocking {
    val child = launch { delay(Long.MAX_VALUE) }
    child.cancel()
    child.join()
    println("parent survived child cancellation")
}
