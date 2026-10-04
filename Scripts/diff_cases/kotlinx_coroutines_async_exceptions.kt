import kotlinx.coroutines.*

fun main() = runBlocking {
    val scope = CoroutineScope(SupervisorJob())
    val completed = scope.async(start = CoroutineStart.UNDISPATCHED) {
        throw IllegalArgumentException("completed")
    }
    try {
        completed.await()
    } catch (e: IllegalArgumentException) {
        println("caught: ${e.message}")
    }
    val pending = scope.async {
        delay(20)
        throw IllegalStateException("pending")
    }
    try {
        pending.await()
    } catch (e: IllegalStateException) {
        println("caught: ${e.message}")
    }
    println(scope.async { 42 }.await())
    scope.cancel()
}
