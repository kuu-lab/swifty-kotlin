package kotlinx.coroutines.selects

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.coroutineContext
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.DisposableHandle
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.yield

public interface SelectClause0 {
    public fun <R> registerSelectClause0(select: SelectBuilder<R>, block: suspend () -> R)
    public operator fun <R> invoke(block: suspend () -> R) {
        registerSelectClause0(currentSelectBuilder<R>(), block)
    }
}

public interface SelectClause1<out Q> {
    public fun <R> registerSelectClause1(select: SelectBuilder<R>, block: suspend (Q) -> R)
    public operator fun <R> invoke(block: suspend (Q) -> R) {
        registerSelectClause1(currentSelectBuilder<R>(), block)
    }
}

public interface SelectClause2<in P, out Q> {
    public fun <R> registerSelectClause2(select: SelectBuilder<R>, param: P, block: suspend (Q) -> R)
    public operator fun <R> invoke(param: P, block: suspend (Q) -> R) {
        registerSelectClause2(currentSelectBuilder<R>(), param, block)
    }
}

public interface SelectBuilder<R> {
    public fun registerClause(ready: () -> Boolean, block: suspend () -> R)
}

@KsSymbolName("__kk_select_builder_exchange")
internal external fun __kkSelectBuilderExchange(builder: Any?): Any?

@KsSymbolName("__kk_select_builder_current")
internal external fun __kkSelectBuilderCurrent(): Any?

internal fun <R> currentSelectBuilder(): SelectBuilder<R> =
    (__kkSelectBuilderCurrent() ?: error("Select clauses require a select builder")) as SelectBuilder<R>

public interface SelectInstance<R> {
    public val context: CoroutineContext
    public fun trySelect(clauseObject: Any, result: Any?): Boolean
    public fun selectInRegistrationPhase(internalResult: Any?)
    public fun disposeOnCompletion(handle: DisposableHandle)
}

public enum class TrySelectDetailedResult {
    SUCCESSFUL, REREGISTER, CANCELLED, ALREADY_SELECTED
}

internal class SelectAlternative<R>(val ready: () -> Boolean, val block: suspend () -> R)

// Readiness is polled in registration order; selectUnbiased uses the same order.
// The runtime does not implement atomic rendezvous between two select waiters.
public class SelectImplementation<R>(override val context: CoroutineContext) : SelectBuilder<R>, SelectInstance<R> {
    private val clauses = mutableListOf<SelectAlternative<R>>()
    private val disposables = mutableListOf<DisposableHandle>()
    private var selected = false

    public override fun registerClause(ready: () -> Boolean, block: suspend () -> R) {
        clauses.add(SelectAlternative(ready, block))
    }

    public override fun trySelect(clauseObject: Any, result: Any?): Boolean {
        if (selected) return false
        selected = true
        return true
    }

    public override fun selectInRegistrationPhase(internalResult: Any?) {
        selected = true
    }

    public override fun disposeOnCompletion(handle: DisposableHandle) {
        if (selected) handle.dispose() else disposables.add(handle)
    }

    internal fun complete() {
        selected = true
        for (handle in disposables) handle.dispose()
        disposables.clear()
    }

    public suspend fun doSelect(): R {
        try {
            while (true) {
                ensureActive()
                for (clause in clauses) {
                    if (clause.ready()) {
                        complete()
                        return clause.block()
                    }
                }
                yield()
            }
        } finally {
            complete()
        }
    }
}

public suspend fun <R> select(builder: SelectBuilder<R>.() -> Unit): R {
    val implementation = SelectImplementation<R>(coroutineContext)
    val previous = __kkSelectBuilderExchange(implementation)
    try {
        builder(implementation)
    } catch (failure: Throwable) {
        implementation.complete()
        throw failure
    } finally {
        __kkSelectBuilderExchange(previous)
    }
    return implementation.doSelect()
}

public suspend fun <R> selectUnbiased(builder: SelectBuilder<R>.() -> Unit): R = select(builder)
