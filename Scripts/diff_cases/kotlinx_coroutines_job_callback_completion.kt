@file:OptIn(InternalCoroutinesApi::class)

import kotlinx.coroutines.*

fun main() = runBlocking {
    val job = launch(start = CoroutineStart.LAZY) {}
    var calls = ""
    job.invokeOnCompletion { cause -> calls += if (cause == null) "A" else "X" }
    val disposed = job.invokeOnCompletion { calls += "X" }
    job.invokeOnCompletion(onCancelling = true, invokeImmediately = false) { calls += "B" }
    disposed.dispose()
    disposed.dispose()
    job.join()
    println(calls)
    job.invokeOnCompletion { cause -> println(cause == null) }.dispose()
    val ignored = job.invokeOnCompletion(false, false) { println("unexpected") }
    println(ignored.toString())
    ignored.dispose()
    NonDisposableHandle.dispose()
    println(NonDisposableHandle.toString())
}
