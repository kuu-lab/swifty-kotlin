package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

import kotlin.internal.KsSymbolName

public interface CoroutineScope {
    public val coroutineContext: CoroutineContext
}

private class ContextScope(
    override val coroutineContext: CoroutineContext,
    val handle: Any
) : CoroutineScope

@KsSymbolName("kk_coroutine_scope_new_with_context")
internal external fun __kkCoroutineScopeNewWithContext(context: CoroutineContext): Any

@KsSymbolName("kk_coroutine_current_context")
internal external fun __kkCurrentCoroutineContext(): CoroutineContext

@DelicateCoroutinesApi
public object GlobalScope : CoroutineScope {
    override val coroutineContext: CoroutineContext
        get() = EmptyCoroutineContext
}

public fun CoroutineScope(context: CoroutineContext): CoroutineScope {
    val scopeContext = if (__kkContextGetJob(context) == null) context + Job() else context
    return ContextScope(scopeContext, __kkNewScopeHandle(scopeContext))
}

public fun MainScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

public val CoroutineScope.isActive: Boolean
    get() = coroutineContext.isActive

public fun CoroutineScope.cancel(cause: CancellationException? = null) {
    val job = __kkContextGetJob(coroutineContext)
        ?: error("Scope cannot be cancelled because it does not have a job")
    __kkJobCancel(job, cause)
}

public fun CoroutineScope.ensureActive() {
    coroutineContext.ensureActive()
}

public suspend fun currentCoroutineContext(): CoroutineContext = __kkCurrentCoroutineContext()

@KsSymbolName("__kk_coroutine_scope_is_runtime")
internal external fun __kkScopeIsRuntime(scope: Any): Boolean

// Runtime builder receivers are opaque handles. Source scope objects retain
// their declared (possibly custom) coroutineContext getter.
internal fun CoroutineScope.__kkScopeContext(): CoroutineContext {
    if (__kkScopeIsRuntime(this)) return __kkCurrentCoroutineContext()
    return coroutineContext
}

internal fun CoroutineScope.__kkScopeHandle(): Any {
    if (__kkScopeIsRuntime(this)) return this
    if (this is ContextScope) return this.handle
    return __kkNewScopeHandle(coroutineContext)
}

private fun __kkNewScopeHandle(context: CoroutineContext): Any {
    val handle = __kkCoroutineScopeNewWithContext(context)
    __kkContextGetJob(context)?.invokeOnCompletion(onCancelling = true) {
        kkCoroutineScopeCancel(handle)
    }
    return handle
}

@KsSymbolName("kk_coroutine_scope_new")
internal external fun kkCoroutineScopeNew(): CoroutineScope

@KsSymbolName("kk_supervisor_scope_new")
internal external fun kkSupervisorScopeNew(): CoroutineScope

@KsSymbolName("kk_coroutine_scope_cancel")
internal external fun kkCoroutineScopeCancel(scope: Any)

@KsSymbolName("kk_coroutine_scope_fail")
internal external fun kkCoroutineScopeFail(scope: Any, exception: Throwable)

@KsSymbolName("kk_coroutine_scope_wait")
internal external fun kkCoroutineScopeWait(scope: Any): Throwable?

// Keep the erased block/result contract for nested generic builders.
// Any? permits nullable results; Sema recovers each call's precise type
// from its block body.
public suspend fun coroutineScope(block: suspend CoroutineScope.() -> Any?): Any? {
    val scope = kkCoroutineScopeNew()
    val result: Any?
    try {
        result = block(scope)
    } catch (e: Throwable) {
        kkCoroutineScopeFail(scope, e)
        val failure = kkCoroutineScopeWait(scope)
        if (failure != null && failure !is CancellationException) {
            throw failure
        }
        throw e
    }
    val failure = kkCoroutineScopeWait(scope)
    if (failure != null) {
        throw failure
    }
    return result
}

public suspend fun supervisorScope(block: suspend CoroutineScope.() -> Any?): Any? {
    val scope = kkSupervisorScopeNew()
    val result: Any?
    try {
        result = block(scope)
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
