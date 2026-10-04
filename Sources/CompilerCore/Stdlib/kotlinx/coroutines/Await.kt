package kotlinx.coroutines


// Small await/join helpers from kotlinx-coroutines Await.kt.

// `awaitCancellation()` lives in the compiler's synthetic registry
// (externalLinkName `kk_await_cancellation`): calls lower to a suspend point
// that parks the caller continuation on the never-completing
// `runtimeNonCancellableJob`, so the coroutine only unwinds via
// cancellation. It cannot live here as a
// bundled body: bundled code cannot reference `NonCancellable` as a `Job`
// (the grafted supertype only exists in user-module sema), and a
// `suspendCoroutineUninterceptedOrReturn` park never observes cancellation.

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
