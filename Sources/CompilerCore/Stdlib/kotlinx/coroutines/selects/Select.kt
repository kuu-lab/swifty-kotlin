package kotlinx.coroutines.selects

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.coroutineContext
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
import kotlinx.coroutines.sync.tryLock
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
    public fun registerClause(ready: () -> Boolean, block: suspend () -> R)

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
        var result = ChannelResult<Any?>(3)
        this@SelectBuilder.registerClause({
            result = __kkSelectTryReceive(channel)
            result.isSuccess || result.isClosed
        }) {
            block(result.getOrThrow() as E)
        }
    }

    public fun <E> ReceiveChannel<E>.onReceiveCatching(block: suspend (ChannelResult<E>) -> R) {
        val channel = this
        var result = ChannelResult<Any?>(3)
        this@SelectBuilder.registerClause({
            result = __kkSelectTryReceive(channel)
            result.isSuccess || result.isClosed
        }) { block(result as ChannelResult<E>) }
    }

    public fun <E> Channel<E>.onSend(element: E, block: suspend (Channel<E>) -> R) {
        val channel = this
        this@SelectBuilder.registerClause({
            val status = __kkSelectTrySend(channel, element)
            if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
            status == 0
        }) { block(channel) }
    }

    public fun <E> SendChannel<E>.onSend(element: E, block: suspend (SendChannel<E>) -> R) {
        val channel = this
        this@SelectBuilder.registerClause({
            val status = __kkSelectTrySend(channel, element)
            if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
            status == 0
        }) { block(channel) }
    }

    public fun Deferred.onAwait(block: suspend (Any) -> R) {
        val deferred = this
        this@SelectBuilder.registerClause({ selectJobReady(deferred) }) { block(deferred.await()) }
    }

    public fun Job.onJoin(block: suspend () -> R) {
        val job = this
        this@SelectBuilder.registerClause({ selectJobReady(job) }, block)
    }

    public fun Mutex.onLock(owner: Any? = null, block: suspend (Mutex) -> R) {
        val mutex = this
        this@SelectBuilder.registerClause({ mutex.tryLock() }) { block(mutex) }
    }

    public fun onTimeout(timeMillis: Long, block: suspend () -> R) {
        val mark = TimeSource.Monotonic.markNow()
        registerClause({ timeMillis <= 0L || mark.elapsedNow().inWholeMilliseconds >= timeMillis }, block)
    }

    public fun onTimeout(timeout: Duration, block: suspend () -> R) {
        onTimeout(timeout.inWholeMilliseconds, block)
    }
}

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
    try {
        builder(implementation)
    } catch (failure: Throwable) {
        implementation.complete()
        throw failure
    }
    return implementation.doSelect()
}

public suspend fun <R> selectUnbiased(builder: SelectBuilder<R>.() -> Unit): R = select(builder)
