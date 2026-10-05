import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch {}
    var calls = 0
    job.invokeOnCompletion { calls++ }
    job.join()
    println(calls)
}
