package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext

import kotlin.internal.KsSymbolName

public interface CoroutineScope {
    public val coroutineContext: CoroutineContext
}

@KsSymbolName("kk_coroutine_scope_new")
internal external fun kkCoroutineScopeNew(): Any

@KsSymbolName("kk_supervisor_scope_new")
internal external fun kkSupervisorScopeNew(): Any

@KsSymbolName("kk_coroutine_scope_cancel")
internal external fun kkCoroutineScopeCancel(scope: Any)

@KsSymbolName("kk_coroutine_scope_wait")
internal external fun kkCoroutineScopeWait(scope: Any): Throwable?

// The block return and function results are typed `Any` rather than a generic
// `<R>`: the compiler cannot yet infer an outer type variable from a lambda body
// whose value is itself a nested generic call (e.g. `async { 7 }.await()`), so a
// generic signature breaks `coroutineScope { async { ... } }`. `Any` mirrors the
// prior synthetic contract and preserves observed behavior; callers rely on the
// usual implicit widening at the use site.
public suspend fun coroutineScope(block: suspend () -> Any): Any {
    val scope = kkCoroutineScopeNew()
    val result: Any
    try {
        result = block()
    } catch (e: Throwable) {
        kkCoroutineScopeCancel(scope)
        kkCoroutineScopeWait(scope)
        throw e
    }
    val failure = kkCoroutineScopeWait(scope)
    if (failure != null) {
        throw failure
    }
    return result
}

public suspend fun supervisorScope(block: suspend () -> Any): Any {
    val scope = kkSupervisorScopeNew()
    val result: Any
    try {
        result = block()
    } catch (e: Throwable) {
        kkCoroutineScopeCancel(scope)
        kkCoroutineScopeWait(scope)
        throw e
    }
    // Supervisor semantics: wait for children but do not propagate their
    // failures; only an exception thrown by the body itself escapes — plus the
    // scope's own cancellation, which kotlinx delivers as a
    // JobCancellationException ("SupervisorCoroutine was cancelled"). Childrens'
    // cancellation results never reach `failure` (filtered inside
    // kk_coroutine_scope_wait), so a CancellationException here can only be the
    // scope's own.
    val failure = kkCoroutineScopeWait(scope)
    if (failure is CancellationException) {
        throw failure
    }
    return result
}

// A direct index loop (rather than `deferreds.map { it.await() }`) avoids
// routing the suspend `.await()` call through the non-suspend collection-HOF
// callable-value adapter.
public suspend fun <T> awaitAll(vararg deferreds: Deferred<T>): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < deferreds.size) {
        result.add(deferreds[i].await())
        i += 1
    }
    return result
}

// Collection-receiver forms of `awaitAll` / `joinAll`. Both use a `for` loop
// over the receiver rather than `map { it.await() }` for the same reason as the
// vararg `awaitAll` above: a suspend lambda handed to a non-`inline` collection
// HOF goes through the callable-value adapter instead of staying in this
// function's CPS frame.
//
// Awaiting sequentially gives fail-fast on the first failure: the exception
// escapes before the remaining elements are awaited. Cancelling the siblings is
// left to structured concurrency (a failing `async` child cancels its parent
// scope), which is also how real kotlinx's `awaitAll` behaves -- it does not
// cancel the other deferreds itself.
public suspend fun <T> Collection<Deferred<T>>.awaitAll(): List<T> {
    val deferreds = this
    val result = mutableListOf<T>()
    for (deferred in deferreds) {
        result.add(deferred.await())
    }
    return result
}

public suspend fun Collection<Job>.joinAll() {
    val jobs = this
    for (job in jobs) {
        job.join()
    }
}
