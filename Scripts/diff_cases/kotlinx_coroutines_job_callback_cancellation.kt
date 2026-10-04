@file:OptIn(InternalCoroutinesApi::class)

import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            delay(1000)
        } finally {
            println("finally")
        }
    }
    job.invokeOnCompletion { cause -> println("complete: ${cause != null}") }
    job.invokeOnCompletion(true, true) { cause -> println("cancelling: ${cause != null}") }
    job.cancel(CancellationException("stop"))
    job.invokeOnCompletion(true, true) { cause -> println("late: ${cause != null}") }
    job.invokeOnCompletion(true, false) { println("unexpected") }.dispose()
    job.invokeOnCompletion(false, false) { println("terminal") }
    job.join()
    println(job.isCancelled)
}
