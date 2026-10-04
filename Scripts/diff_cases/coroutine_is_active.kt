import kotlinx.coroutines.*

// Regression: the bare isActive property inside a launched coroutine must use
// the running job rather than a synthetic global symbol.
fun main() = runBlocking {
    var active = false
    val job = launch { active = isActive }
    job.join()
    println("active: $active")
}
