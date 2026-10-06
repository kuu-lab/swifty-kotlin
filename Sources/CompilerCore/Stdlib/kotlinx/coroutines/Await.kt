package kotlinx.coroutines


// Small await/join helpers from kotlinx-coroutines Await.kt.

// `awaitCancellation()` lives in the compiler's synthetic registry
// (externalLinkName `kk_await_cancellation`): calls lower to a suspend point
// that parks a cancellable continuation linked to the caller's Job.
// Cancellation wakes the parked continuation even when it is not the
// Job's launcher continuation (e.g. inside a scope-builder block).

// Top-level parameter forms of `joinAll` / `awaitAll`. The
// `Collection<Deferred<T>>.awaitAll()` / `Collection<Job>.joinAll()` receivers
// in CoroutineScope.kt cover the `list.awaitAll()` call shape; these cover
// `joinAll(j1, j2)` / `awaitAll(list)`, which real kotlinx also declares
// top-level in Await.kt. They delegate to the receiver forms so sequential
// fail-fast ordering stays identical in both spellings.
public suspend fun joinAll(vararg jobs: Job) {
    for (job in jobs) {
        job.join()
    }
}

public suspend fun <T> awaitAll(deferreds: Collection<Deferred<T>>): List<T> = deferreds.awaitAll()
