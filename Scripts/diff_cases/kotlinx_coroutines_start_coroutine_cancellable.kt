// KUU-2689: startCoroutineCancellable must actually start the block in the
// completion's context: synchronous values and thrown exceptions reach the
// completion, a dispatcher context routes the start through interception, and
// a Job that is no longer active at the resume boundary suppresses the block
// and completes with CancellationException.

import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.*
import kotlinx.coroutines.intrinsics.startCoroutineCancellable

@OptIn(InternalCoroutinesApi::class)
fun main() = runBlocking {
    var sideEffects = 0

    // Synchronous completion: no interceptor, the block runs inline.
    val syncCompletion = Continuation<Int>(EmptyCoroutineContext) { result ->
        println("sync:" + result.getOrThrow())
    }
    val immediate: suspend () -> Int = {
        sideEffects++
        42
    }
    immediate.startCoroutineCancellable(syncCompletion)
    println("sync-effects:" + sideEffects)

    // A thrown exception is delivered to the completion.
    val errorCompletion = Continuation<Int>(EmptyCoroutineContext) { result ->
        println("error:" + (result.exceptionOrNull() is IllegalStateException))
    }
    val failing: suspend () -> Int = {
        sideEffects++
        throw IllegalStateException("boom")
    }
    failing.startCoroutineCancellable(errorCompletion)
    println("error-effects:" + sideEffects)

    // Dispatch through a dispatcher context: interception still runs the block
    // once the resume reaches the dispatcher queue.
    var dispatched = false
    val dispatchedCompletion = Continuation<Int>(Dispatchers.Default) { result ->
        println("dispatched:" + result.getOrThrow())
        dispatched = true
    }
    val dispatchedBlock: suspend () -> Int = {
        sideEffects++
        7
    }
    dispatchedBlock.startCoroutineCancellable(dispatchedCompletion)
    while (!dispatched) {
        delay(1)
    }
    println("dispatch-effects:" + sideEffects)

    // A Job already cancelled before the dispatched resume reaches the
    // coroutine suppresses the block and completes with CancellationException.
    val cancelledJob = Job()
    cancelledJob.cancel()
    var cancelObserved = false
    val cancelledCompletion = Continuation<Int>(Dispatchers.Default + cancelledJob) { result ->
        println("cancelled:" + (result.exceptionOrNull() is CancellationException))
        cancelObserved = true
    }
    val suppressedBlock: suspend () -> Int = {
        sideEffects++
        println("SIDE EFFECT")
        1
    }
    suppressedBlock.startCoroutineCancellable(cancelledCompletion)
    while (!cancelObserved) {
        delay(1)
    }
    println("cancel-effects:" + sideEffects)
}
