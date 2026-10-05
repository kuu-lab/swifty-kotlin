@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

import kotlinx.coroutines.*

fun main() = runBlocking {
    val deferred = CompletableDeferred<Int>()
    val view: Deferred<Int> = deferred
    val job: Job = view
    println(job.isActive)
    try {
        view.getCompleted()
    } catch (e: IllegalStateException) {
        println("not completed")
    }
    try {
        view.getCompletionExceptionOrNull()
    } catch (e: IllegalStateException) {
        println("no completion yet")
    }
    launch {
        delay(1)
        println(deferred.complete(42))
        println(deferred.complete(99))
    }
    println(view.await())
    println(view.getCompleted())
    println(view.getCompleted() + 1)
    println(view.getCompletionExceptionOrNull() == null)
    println(job.isCompleted)
    println(job.isActive)
    println(CompletableDeferred("ready").await())
    println(CompletableDeferred("ready").getCompleted().length)
    println(CompletableDeferred<String?>(value = null).getCompleted())
    println(awaitAll(CompletableDeferred(1), CompletableDeferred(2)))
    println(listOf(CompletableDeferred(3), CompletableDeferred(4)).awaitAll())
    val task = async { 7 }
    println(task.await())
    println(task.getCompleted())
    println(task.getCompletionExceptionOrNull() == null)
}
