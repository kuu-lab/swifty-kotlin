// KUU-3973: dropbox/Store 5.0.0 multicast Actor.kt imports
// kotlinx.coroutines.CompletionHandler and forwards a stored
// `CompletionHandler?` to Job.invokeOnCompletion(handler = ...).
// The wildcard keeps `Job.invokeOnCompletion` visible on both backends:
// upstream declares it as a Job member while the bundled coroutines model it
// as a package-level extension (its importable top-level counterpart is
// internal upstream, so an explicit import would not compile under kotlinc).
import kotlinx.coroutines.*
import kotlinx.coroutines.CompletionHandler

// Mirrors org.mobilenativefoundation.store.multicast5.Actor.actor: the
// handler travels as a nullable `CompletionHandler?` parameter and is
// registered on the launched job only when non-null.
private fun CoroutineScope.actor(
    onCompletion: CompletionHandler? = null,
    block: suspend CoroutineScope.() -> Unit,
): Job {
    val job = launch { block() }
    if (onCompletion != null) job.invokeOnCompletion(handler = onCompletion)
    return job
}

fun main() = runBlocking {
    // Stored handler fires once with a null cause on normal completion.
    var completed = ""
    val handler: CompletionHandler = { cause -> completed += if (cause == null) "ok" else "fail" }
    actor(handler) { delay(1) }.join()
    println("stored:$completed")

    // A null handler skips registration; the actor body still runs.
    var calls = 0
    actor(null) { calls++ }.join()
    println("no-handler:$calls")

    // The typealias is transparent: values convert both ways with the raw
    // function type and a stored handler can be invoked directly.
    val raw: (cause: Throwable?) -> Unit = handler
    val aliased: CompletionHandler = raw
    aliased(null)
    println("invoked:$completed")

    // Cancellation delivers a CancellationException cause to the handler.
    var cancelCause = ""
    val cancelled = actor(
        { cause -> cancelCause = if (cause is CancellationException) "cancelled" else "other" }
    ) { delay(1000) }
    cancelled.cancel()
    cancelled.join()
    println("cancelled:$cancelCause")
}
