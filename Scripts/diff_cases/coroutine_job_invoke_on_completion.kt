@file:OptIn(InternalCoroutinesApi::class)

import kotlinx.coroutines.*

// Regression: Job.invokeOnCompletion / Job.getCancellationException /
// CoroutineContext.job / DisposableHandle -- unblocks Ktor's
// `job.invokeOnCompletion(onCancelling = true) { channel.cancel(it) }` /
// `this.coroutineContext.job.getCancellationException()` pattern.
fun main() = runBlocking {
    // Normal completion: handler sees a null cause.
    val job = launch {}
    var handlerCalls = 0
    var sawNullCause = false
    job.invokeOnCompletion { cause ->
        handlerCalls++
        sawNullCause = cause == null
    }
    job.join()
    println(handlerCalls)
    println(sawNullCause)

    // onCancelling handler fires (with a non-null cause) once cancellation is
    // observed, ahead of full completion.
    val job2 = launch { delay(1000) }
    var cancellingFired = false
    job2.invokeOnCompletion(onCancelling = true) {
        cancellingFired = it != null
    }
    job2.cancel()
    job2.join()
    println(job2.isCancelled)
    println(cancellingFired)
    println(job2.getCancellationException() is CancellationException)

    // CoroutineContext.job resolves to the enclosing job (checked at the
    // unambiguous top level of runBlocking; giving CoroutineScope's builder
    // blocks a real receiver type, so `this.coroutineContext` resolves
    // correctly inside a nested `launch { }`, remains a separate, larger gap
    // -- see the registration comment in
    // HeaderHelpers+SyntheticCoroutineRegistry.swift).
    println(coroutineContext.job.isActive)

    // dispose() removes a handler before it has a chance to fire.
    val job3 = launch { delay(1000) }
    var disposedCallRan = false
    val handle = job3.invokeOnCompletion { disposedCallRan = true }
    handle.dispose()
    job3.cancel()
    job3.join()
    println(disposedCallRan)
}
