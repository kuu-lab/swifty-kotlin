package kotlinx.coroutines

import kotlin.internal.KsSymbolName

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
    // failures; only an exception thrown by the body itself escapes.
    kkCoroutineScopeWait(scope)
    return result
}

// A direct index loop (rather than `deferreds.map { it.await() }`) avoids
// routing the suspend `.await()` call through the non-suspend collection-HOF
// callable-value adapter.
public suspend fun awaitAll(vararg deferreds: Deferred): List<Any> {
    val result = mutableListOf<Any>()
    var i = 0
    while (i < deferreds.size) {
        result.add(deferreds[i].await())
        i += 1
    }
    return result
}
