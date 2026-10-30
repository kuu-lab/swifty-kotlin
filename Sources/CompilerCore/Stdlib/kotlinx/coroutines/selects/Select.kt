package kotlinx.coroutines.selects

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.coroutineContext
import kotlin.internal.KsSymbolName
import kotlin.time.Duration
import kotlin.time.TimeSource
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.DisposableHandle
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ChannelResult
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.yield

public interface SelectClause0 {
    public fun <R> registerSelectClause0(select: SelectBuilder<R>, block: suspend () -> R)
}

public interface SelectClause1<out Q> {
    public fun <R> registerSelectClause1(select: SelectBuilder<R>, block: suspend (Q) -> R)
}

public interface SelectClause2<in P, out Q> {
    public fun <R> registerSelectClause2(select: SelectBuilder<R>, param: P, block: suspend (Q) -> R)
}

// Clause registration lives on SelectBuilder as member extensions so every
// callback's return type is bound to the builder's R: `select { ... }` infers
// its result type from the clauses instead of introducing an independent R
// per clause call.
public interface SelectBuilder<R> {
    // `ready` is invoked with the clause's runtime registration token.
    // Channel and mutex clauses pass it to their poll bridge so the outcome
    // is committed through the select's atomic claim — the same channel
    // rendezvous cannot feed two clauses — instead of a bare try-operation.
    public fun registerClause(ready: (clauseToken: Any) -> Boolean, block: suspend () -> R)

    public operator fun SelectClause0.invoke(block: suspend () -> R) {
        registerSelectClause0(this@SelectBuilder, block)
    }

    public operator fun <Q> SelectClause1<Q>.invoke(block: suspend (Q) -> R) {
        registerSelectClause1(this@SelectBuilder, block)
    }

    public operator fun <P, Q> SelectClause2<P, Q>.invoke(param: P, block: suspend (Q) -> R) {
        registerSelectClause2(this@SelectBuilder, param, block)
    }

    public fun <E> ReceiveChannel<E>.onReceive(block: suspend (E) -> R) {
        val channel = this
        var result: ChannelResult<Any?>? = null
        this@SelectBuilder.registerClause({ token ->
            val polled = __kkSelectPollReceive(channel, token)
            result = polled
            polled.isSuccess || polled.isClosed
        }) {
            block(result!!.getOrThrow() as E)
        }
    }

    @Suppress("UNCHECKED_CAST")
    public fun <E> ReceiveChannel<E>.onReceiveCatching(block: suspend (ChannelResult<E>) -> R) {
        val channel = this
        var result: ChannelResult<Any?>? = null
        this@SelectBuilder.registerClause({ token ->
            val polled = __kkSelectPollReceive(channel, token)
            result = polled
            polled.isSuccess || polled.isClosed
        }) { block(result!! as ChannelResult<E>) }
    }

    public fun <E> Channel<E>.onSend(element: E, block: suspend (Channel<E>) -> R) {
        val channel = this
        this@SelectBuilder.registerClause({ token ->
            val status = __kkSelectPollSend(channel, token, element)
            if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
            status == 0
        }) { block(channel) }
    }

    public fun <E> SendChannel<E>.onSend(element: E, block: suspend (SendChannel<E>) -> R) {
        val channel = this
        this@SelectBuilder.registerClause({ token ->
            val status = __kkSelectPollSend(channel, token, element)
            if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
            status == 0
        }) { block(channel) }
    }

    public fun <T> Deferred<T>.onAwait(block: suspend (T) -> R) {
        val deferred = this
        this@SelectBuilder.registerClause({ selectJobReady(deferred) }) { block(deferred.await()) }
    }

    public fun Job.onJoin(block: suspend () -> R) {
        val job = this
        this@SelectBuilder.registerClause({ selectJobReady(job) }, block)
    }

    public fun Mutex.onLock(owner: Any? = null, block: suspend (Mutex) -> R) {
        val mutex = this
        this@SelectBuilder.registerClause({ token -> selectLockReady(__kkSelectPollLock(mutex, token, owner)) }) {
            block(mutex)
        }
    }

    public fun onTimeout(timeMillis: Long, block: suspend () -> R) {
        val mark = TimeSource.Monotonic.markNow()
        registerClause({ timeMillis <= 0L || mark.elapsedNow().inWholeMilliseconds >= timeMillis }, block)
    }

    public fun onTimeout(timeout: Duration, block: suspend () -> R) {
        onTimeout(timeout.inWholeMilliseconds, block)
    }
}

@KsSymbolName("__kk_select_builder_exchange")
internal external fun __kkSelectBuilderExchange(builder: Any?): Any?

@KsSymbolName("__kk_select_builder_current")
internal external fun __kkSelectBuilderCurrent(): Any?

@KsSymbolName("__kk_select_state_new")
internal external fun __kkSelectStateNew(): Any

@KsSymbolName("__kk_select_clause_new")
internal external fun __kkSelectClauseNew(state: Any): Any

@KsSymbolName("__kk_select_try_select")
internal external fun __kkSelectTrySelect(clause: Any): Int

@KsSymbolName("__kk_select_try_select_result")
internal external fun __kkSelectTrySelectResult(clause: Any, result: Any?): Int

@KsSymbolName("__kk_select_mark_selected")
internal external fun __kkSelectMarkSelected(state: Any): Int

@KsSymbolName("__kk_select_selected_clause")
internal external fun __kkSelectSelectedClause(state: Any): Any?

@KsSymbolName("__kk_select_state_finish")
internal external fun __kkSelectStateFinish(state: Any): Int

@KsSymbolName("__kk_select_poll_receive")
internal external fun __kkSelectPollReceive(channel: Channel<*>, clause: Any): ChannelResult<Any?>

@KsSymbolName("__kk_select_poll_send")
internal external fun __kkSelectPollSend(channel: Any, clause: Any, value: Any?): Int

@KsSymbolName("__kk_select_poll_lock")
internal external fun __kkSelectPollLock(mutex: Mutex, clause: Any, owner: Any?): Int

// A lock poll returns 1 once the clause owns the mutex, 0 while the mutex is
// held elsewhere or the select already decided for another clause, and 2 for
// the same-owner IllegalStateException upstream `Mutex.tryLock(owner)`
// reports.
internal fun selectLockReady(status: Int): Boolean {
    if (status == 2) throw IllegalStateException("This mutex is already locked by the specified owner")
    return status == 1
}

@Suppress("UNCHECKED_CAST")
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

internal class SelectAlternative<R>(val reg: Any, val ready: (Any) -> Boolean, val block: suspend () -> R)

public class SelectImplementation<R>(override val context: CoroutineContext) : SelectBuilder<R>, SelectInstance<R> {
    private val selectState: Any = __kkSelectStateNew()
    private val clauses = mutableListOf<SelectAlternative<R>>()
    private val disposables = mutableListOf<DisposableHandle>()
    private var selected = false

    public override fun registerClause(ready: (Any) -> Boolean, block: suspend () -> R) {
        clauses.add(SelectAlternative(__kkSelectClauseNew(selectState), ready, block))
    }

    public override fun trySelect(clauseObject: Any, result: Any?): Boolean =
        __kkSelectTrySelectResult(clauseObject, result) != 0

    public override fun selectInRegistrationPhase(internalResult: Any?) {
        selected = true
        __kkSelectMarkSelected(selectState)
    }

    public override fun disposeOnCompletion(handle: DisposableHandle) {
        if (selected) handle.dispose() else disposables.add(handle)
    }

    internal fun complete() {
        selected = true
        // Mark the state finished and drop every parked channel offer so a
        // completed or cancelled select can no longer consume a rendezvous.
        __kkSelectStateFinish(selectState)
        for (handle in disposables) handle.dispose()
        disposables.clear()
    }

    public suspend fun doSelect(): R {
        try {
            while (true) {
                ensureActive()
                for (clause in clauses) {
                    // `ready` reports an outcome committed for this clause —
                    // by its own poll or by an external claimant resolving a
                    // parked offer. trySelect finalizes the selection
                    // atomically: the first clause to claim the select wins
                    // and a losing clause never executes its block.
                    if (clause.ready(clause.reg) && __kkSelectTrySelect(clause.reg) != 0) {
                        complete()
                        return clause.block()
                    }
                }
                // A counterparty (send/receive/close) may have claimed one of
                // this select's parked waiters between polls; dispatch its
                // clause instead of spinning past it.
                val winner = __kkSelectSelectedClause(selectState)
                if (winner != null) {
                    complete()
                    return runSelectedClause(winner)
                }
                yield()
            }
        } finally {
            complete()
        }
    }

    private suspend fun runSelectedClause(reg: Any): R {
        val clause = clauses.firstOrNull { it.reg === reg }
            ?: error("select was selected by an unregistered clause")
        // KUU-3848: a counterparty may have committed this clause's outcome
        // by claiming its parked offer between this select's polls. The
        // clause's captured poll variable (`result` for onReceive clauses)
        // still holds the earlier "not ready" box, so re-poll to materialize
        // the delivered status/value before the block observes it — every
        // poll bridge answers a committed `clause.delivered` idempotently.
        clause.ready(clause.reg)
        return clause.block()
    }

    // Upstream `UnbiasedSelectImplementation` shuffles the clause
    // registration list before selecting so simultaneously-ready clauses win
    // with equal probability; `select` keeps registration order on purpose.
    internal fun shuffleClauses() {
        clauses.shuffle()
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

public suspend fun <R> selectUnbiased(builder: SelectBuilder<R>.() -> Unit): R {
    val implementation = SelectImplementation<R>(coroutineContext)
    val previous = __kkSelectBuilderExchange(implementation)
    try {
        builder(implementation)
        implementation.shuffleClauses()
    } catch (failure: Throwable) {
        implementation.complete()
        throw failure
    } finally {
        __kkSelectBuilderExchange(previous)
    }
    return implementation.doSelect()
}
