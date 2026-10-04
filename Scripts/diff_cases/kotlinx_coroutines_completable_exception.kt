@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

import kotlinx.coroutines.*

fun main() = runBlocking {
    val deferred = CompletableDeferred<Int>()
    val failure = IllegalStateException("failed")
    println(deferred.completeExceptionally(failure))
    println(deferred.complete(1))
    println(deferred.completeExceptionally(failure))
    println(deferred.getCompletionExceptionOrNull() === failure)
    println(deferred.isCancelled)
    println(deferred.isCompleted)
    try {
        deferred.getCompleted()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    try {
        deferred.await()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    val pending = CompletableDeferred<Int>()
    launch {
        delay(1)
        pending.completeExceptionally(IllegalStateException("late failure"))
    }
    try {
        pending.await()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    val parent = Job()
    val child = CompletableDeferred<Int>(parent = parent)
    parent.cancel()
    println(child.isCancelled)
    println(child.isCompleted)
    println(child.complete(2))
    try {
        child.await()
    } catch (e: CancellationException) {
        println("cancelled")
    }
    val cancelledParent = Job()
    cancelledParent.cancel()
    val lateChild = CompletableDeferred<Int>(parent = cancelledParent)
    println(lateChild.isCancelled)
}
