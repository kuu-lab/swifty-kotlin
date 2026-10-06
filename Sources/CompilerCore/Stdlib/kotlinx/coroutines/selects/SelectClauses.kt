package kotlinx.coroutines.selects

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ChannelResult
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.tryLock

@KsSymbolName("__kk_select_try_receive")
internal external fun __kkSelectTryReceive(channel: Channel<*>): ChannelResult<Any?>

@KsSymbolName("kk_channel_try_send")
internal external fun __kkSelectTrySend(channel: Any, value: Any?): Int

@KsSymbolName("kk_job_is_completed")
internal external fun __kkSelectIsCompleted(job: Any): Int

@KsSymbolName("__kk_select_start_job")
internal external fun __kkSelectStart(job: Any): Boolean

internal class SelectClause0Impl(val ready: () -> Boolean) : SelectClause0 {
    override fun <R> registerSelectClause0(select: SelectBuilder<R>, block: suspend () -> R) {
        select.registerClause(ready, block)
    }
}

internal class SelectClause1Impl<Q>(val ready: () -> Boolean, val value: suspend () -> Q) : SelectClause1<Q> {
    override fun <R> registerSelectClause1(select: SelectBuilder<R>, block: suspend (Q) -> R) {
        select.registerClause(ready) { block(value()) }
    }
}

internal class SelectClause2Impl<P, Q>(val ready: (P) -> Boolean, val value: (P) -> Q) : SelectClause2<P, Q> {
    override fun <R> registerSelectClause2(select: SelectBuilder<R>, param: P, block: suspend (Q) -> R) {
        select.registerClause({ ready(param) }) { block(value(param)) }
    }
}

public val ReceiveChannel<*>.onReceive: SelectClause1<Any?>
    get() {
        var result: ChannelResult<Any?>? = null
        return SelectClause1Impl({
            val polled = __kkSelectTryReceive(this)
            result = polled
            polled.isSuccess || polled.isClosed
        }, { result!!.getOrThrow() })
    }

public val ReceiveChannel<*>.onReceiveCatching: SelectClause1<ChannelResult<Any?>>
    get() {
        var result: ChannelResult<Any?>? = null
        return SelectClause1Impl({
            val polled = __kkSelectTryReceive(this)
            result = polled
            polled.isSuccess || polled.isClosed
        }, { result!! })
    }

public fun <E, R> ReceiveChannel<E>.onReceive(block: suspend (E) -> R) {
    var result: ChannelResult<Any?>? = null
    currentSelectBuilder<R>().registerClause({
        val polled = __kkSelectTryReceive(this)
        result = polled
        polled.isSuccess || polled.isClosed
    }) { block(result!!.getOrThrow() as E) }
}

@Suppress("UNCHECKED_CAST")
public fun <E, R> ReceiveChannel<E>.onReceiveCatching(block: suspend (ChannelResult<E>) -> R) {
    var result: ChannelResult<Any?>? = null
    currentSelectBuilder<R>().registerClause({
        val polled = __kkSelectTryReceive(this)
        result = polled
        polled.isSuccess || polled.isClosed
    }) { block(result!! as ChannelResult<E>) }
}

public fun <E, R> Channel<E>.onSend(element: E, block: suspend (Channel<E>) -> R) {
    currentSelectBuilder<R>().registerClause({
        val status = __kkSelectTrySend(this, element)
        if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
        status == 0
    }) { block(this) }
}

public fun <E, R> SendChannel<E>.onSend(element: E, block: suspend (SendChannel<E>) -> R) {
    currentSelectBuilder<R>().registerClause({
        val status = __kkSelectTrySend(this, element)
        if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
        status == 0
    }) { block(this) }
}

public val Channel<*>.onSend: SelectClause2<Any?, Channel<*>>
    get() = SelectClause2Impl({ value ->
        val status = __kkSelectTrySend(this, value)
        if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
        status == 0
    }, { this })

public val SendChannel<*>.onSend: SelectClause2<Any?, SendChannel<*>>
    get() = SelectClause2Impl({ value ->
        val status = __kkSelectTrySend(this, value)
        if (status == 1 || status == 2) throw IllegalStateException("Channel was closed")
        status == 0
    }, { this })

public val Deferred<*>.onAwait: SelectClause1<Any?>
    get() = SelectClause1Impl({ selectJobReady(this) }, { await() })

public val Job.onJoin: SelectClause0
    get() = SelectClause0Impl({ selectJobReady(this) })

internal fun selectJobReady(job: Any): Boolean {
    __kkSelectStart(job)
    return __kkSelectIsCompleted(job) != 0
}

public fun <T, R> Deferred<T>.onAwait(block: suspend (T) -> R) {
    currentSelectBuilder<R>().registerClause({ selectJobReady(this) }) { block(await()) }
}

public fun <R> Job.onJoin(block: suspend () -> R) {
    currentSelectBuilder<R>().registerClause({ selectJobReady(this) }, block)
}

public val Mutex.onLock: SelectClause2<Any?, Mutex>
    get() = SelectClause2Impl({ tryLock() }, { this })
public fun <R> Mutex.onLock(owner: Any? = null, block: suspend (Mutex) -> R) {
    currentSelectBuilder<R>().registerClause({ tryLock() }) { block(this) }
}
