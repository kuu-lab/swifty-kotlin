/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Flow.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.internal.KsSymbolName
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.cancel
import kotlinx.coroutines.channels.close
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.channels.receiveCatching

public interface Flow<out T>

@KsSymbolName("kk_flow_collect")
internal external suspend fun <T> Flow<T>.collectCold(collector: suspend (T) -> Unit)

@Suppress("UNCHECKED_CAST")
public suspend fun <T> Flow<T>.collect(collector: suspend (T) -> Unit) {
    if (this is ChannelFlow<*>) {
        @Suppress("UNCHECKED_CAST")
        (this as ChannelFlow<T>).collectTo(collector)
    } else if (this is SharedFlow<*>) {
        (this as SharedFlow<T>).collect(collector)
    } else {
        this.collectCold { value -> collector(value) }
    }
}

public suspend fun <T> Flow<T>.collect(collector: FlowCollector<T>) {
    this.collect { value -> collector.emit(value) }
}

// MIGRATION-FLOW-004 (KSP-499)
// Flow operators are bundled Kotlin source. Most operators compose the
// cold-flow core (`flow`, `emit`, and `collect`); latest flattening uses its
// runtime bridge so cancellation reaches a suspended inner emitter.

public fun <T, R> Flow<T>.map(transform: suspend (T) -> R): Flow<R> {
    val source = this
    return flow {
        source.collect { value ->
            emit(transform(value))
        }
    }
}

public fun <T> Flow<T>.filter(predicate: suspend (T) -> Boolean): Flow<T> {
    val source = this
    return flow {
        source.collect { value ->
            if (predicate(value)) {
                emit(value)
            }
        }
    }
}

public fun <T> Flow<T>.take(count: Int): Flow<T> {
    require(count > 0) { "Requested element count $count should be positive" }
    val source = this
    return flow {
        val collector = SendingCollector<T> { value -> emit(value) }
        var emitted = 0
        try {
            source.collect { value ->
                collector.emit(value)
                emitted += 1
                if (emitted == count) throw AbortFlowException(collector)
            }
        } catch (e: AbortFlowException) {
            if (e.owner !== collector) throw e
        }
    }
}

public suspend fun <T> Flow<T>.toList(): List<T> {
    val source = this
    val result = mutableListOf<T>()
    source.collect { value -> result.add(value) }
    return result
}

public suspend fun <T> Flow<T>.first(): T {
    val source = this
    var found = false
    var result: Any? = null
    val collector = SendingCollector<T> { value ->
        result = value
        found = true
    }
    try {
        source.collect { value ->
            collector.emit(value)
            throw AbortFlowException(collector)
        }
    } catch (e: AbortFlowException) {
        if (e.owner !== collector) throw e
    }
    if (!found) throw NoSuchElementException("Flow is empty.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public suspend fun <T> Flow<T>.single(): T {
    val source = this
    var count = 0
    var result: Any? = null
    source.collect { value ->
        count += 1
        if (count == 1) result = value
    }
    if (count == 0) throw NoSuchElementException("Flow is empty.")
    if (count > 1) throw IllegalArgumentException("Flow has more than one element.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public suspend fun <T> Flow<T>.count(): Int {
    val source = this
    var count = 0
    source.collect { count += 1 }
    return count
}

public suspend fun <T, R> Flow<T>.fold(
    initial: R,
    operation: suspend (R, T) -> R
): R {
    val source = this
    var result = initial
    source.collect { value -> result = operation(result, value) }
    return result
}

public suspend fun <T> Flow<T>.reduce(operation: suspend (T, T) -> T): T {
    val source = this
    var found = false
    var result: Any? = null
    source.collect { value ->
        if (!found) {
            result = value
            found = true
        } else {
            @Suppress("UNCHECKED_CAST")
            result = operation(result as T, value)
        }
    }
    if (!found) throw NoSuchElementException("Flow is empty.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public fun <T, R> Flow<T>.flatMapConcat(transform: suspend (T) -> Flow<R>): Flow<R> {
    val source = this
    return flow {
        source.collect { value ->
            val inner = transform(value)
            inner.collect { emit(it) }
        }
    }
}

public fun <T, R> Flow<T>.flatMapMerge(
    concurrency: Int,
    transform: suspend (T) -> Flow<R>
): Flow<R> {
    require(concurrency > 0) { "Expected positive concurrency level, but had $concurrency" }
    return flatMapConcat(transform)
}

public fun <T, R> Flow<T>.flatMapMerge(
    transform: suspend (T) -> Flow<R>
): Flow<R> = flatMapMerge(DEFAULT_CONCURRENCY, transform)

public fun <T, R> Flow<T>.flatMapLatest(transform: suspend (T) -> Flow<R>): Flow<R> =
    flatMapLatestRuntime(this, transform)

@KsSymbolName("__kk_flow_flat_map_latest_external")
internal external fun <T, R> flatMapLatestRuntime(
    source: Flow<T>,
    transform: suspend (T) -> Flow<R>
): Flow<R>

public fun <T, R, V> Flow<T>.zip(
    other: Flow<R>,
    transform: suspend (T, R) -> V
): Flow<V> {
    val source = this
    return flow {
        coroutineScope {
            val otherValues = Channel<R>(Channel.RENDEZVOUS)
            val otherJob = launch {
                try {
                    other.collect { value -> otherValues.send(value) }
                    otherValues.close()
                } catch (failure: Throwable) {
                    otherValues.close(failure)
                    throw failure
                }
            }
            val zipOwner = Any()
            val collector = SendingCollector<T> { left ->
                val received = otherValues.receiveCatching()
                if (!received.isSuccess) {
                    val failure = received.exceptionOrNull()
                    if (failure != null) throw failure
                    throw AbortFlowException(zipOwner)
                }
                emit(transform(left, received.getOrThrow()))
            }
            try {
                source.collect { value -> collector.emit(value) }
            } catch (failure: AbortFlowException) {
                if (failure.owner !== zipOwner) throw failure else Unit
            } finally {
                otherJob.cancel()
                otherValues.cancel()
            }
        }
    }
}

private class FlowCombineEvent(val index: Int, val value: Any?, val completed: Boolean)

// Collect every input in its own child and feed updates through a bounded
// channel. The channel preserves backpressure while letting the downstream
// transform run as soon as each input has produced its first value.
internal fun <T, R> combineInternal(
    flows: List<Flow<T>>,
    transform: suspend FlowCollector<R>.(Array<T>) -> Unit
): Flow<R> = flow {
    val count = flows.size
    if (count == 0) return@flow

    coroutineScope {
        val updates = Channel<FlowCombineEvent>(count)
        val jobs = mutableListOf<Job>()
        var sourceIndex = 0
        for (source in flows) {
            val index = sourceIndex
            sourceIndex += 1
            jobs.add(launch {
                try {
                    source.collect { value -> updates.send(FlowCombineEvent(index, value, false)) }
                    updates.send(FlowCombineEvent(index, null, true))
                } catch (failure: Throwable) {
                    updates.close(failure)
                    throw failure
                }
            })
        }

        val latest = arrayOfNulls<Any?>(count)
        val hasValue = BooleanArray(count)
        val collector = SendingCollector<R> { value -> emit(value) }
        var missingValues = count
        var completed = 0
        try {
            while (completed < count) {
                val received = updates.receiveCatching()
                if (!received.isSuccess) {
                    val failure = received.exceptionOrNull()
                    if (failure != null) throw failure
                    break
                }
                val event = received.getOrThrow()
                if (event.completed) {
                    completed += 1
                    if (!hasValue[event.index]) {
                        for (job in jobs) job.cancel()
                        updates.cancel()
                        break
                    }
                } else {
                    if (!hasValue[event.index]) {
                        hasValue[event.index] = true
                        missingValues -= 1
                    }
                    latest[event.index] = event.value
                    if (missingValues == 0) {
                        val values = arrayOfNulls<Any?>(count)
                        var index = 0
                        while (index < count) {
                            values[index] = latest[index]
                            index += 1
                        }
                        @Suppress("UNCHECKED_CAST")
                        transform(collector, values as Array<T>)
                    }
                }
            }
        } catch (failure: Throwable) {
            for (job in jobs) job.cancel()
            updates.cancel()
            throw failure
        }
    }
}

public fun <T, R, V> Flow<T>.combine(
    other: Flow<R>,
    transform: suspend (T, R) -> V
): Flow<V> {
    return combineInternal<Any?, V>(listOf<Flow<Any?>>(this, other)) { values ->
        @Suppress("UNCHECKED_CAST")
        emit(transform(values[0] as T, values[1] as R))
    }
}

public fun <T> merge(vararg flows: Flow<T>): Flow<T> = flow {
    for (source in flows) {
        source.collect { value -> emit(value) }
    }
}

@FlowPreview
public fun <T> Flow<T>.debounce(timeoutMillis: Long): Flow<T> {
    val source = this
    return flow { source.collect { value -> emit(value) } }
}

// Buffering and context operators use a per-collection channel. Their fused
// configuration lives in ChannelFlow so adjacent operators share one producer
// and one channel.

public fun <T> Flow<T>.buffer(
    capacity: Int = Channel.BUFFERED,
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND
): Flow<T> {
    require(capacity >= 0 || capacity == Channel.BUFFERED || capacity == Channel.CONFLATED) {
        "Buffer size should be non-negative, BUFFERED, or CONFLATED, but was $capacity"
    }
    require(capacity != Channel.CONFLATED || onBufferOverflow == BufferOverflow.SUSPEND) {
        "CONFLATED capacity cannot be used with non-default onBufferOverflow"
    }
    val actualCapacity = if (capacity == Channel.CONFLATED) 0 else capacity
    val actualOverflow = if (capacity == Channel.CONFLATED) {
        BufferOverflow.DROP_OLDEST
    } else {
        onBufferOverflow
    }
    return fuse(EmptyCoroutineContext, actualCapacity, actualOverflow)
}

public fun <T> Flow<T>.conflate(): Flow<T> =
    fuse(EmptyCoroutineContext, 0, BufferOverflow.DROP_OLDEST)

public fun <T> Flow<T>.flowOn(context: kotlin.coroutines.CoroutineContext): Flow<T> {
    val containsJob = context.fold(false) { found, element ->
        found || element is kotlinx.coroutines.Job
    }
    require(!containsJob) {
        "Flow context cannot contain job in it. Had $context"
    }
    return fuse(context, OPTIONAL_CHANNEL_CAPACITY, BufferOverflow.SUSPEND)
}

// KSwiftK compatibility surface: `flowWith` was removed from kotlinx-coroutines
// (~1.4.x; absent in 1.10.2). Keep it as an alias of flowOn for compatibility.
public fun <T> Flow<T>.flowWith(flowContext: kotlin.coroutines.CoroutineContext): Flow<T> =
    flowOn(flowContext)

// `cancellable` is the exception to the pass-throughs above: it composes the
// retained collect/emit core with `ensureActive`, so a collector running in a
// cancelled coroutine stops between elements instead of draining the upstream
// sequence (KSP-1577).
public fun <T> Flow<T>.cancellable(): Flow<T> {
    val source = this
    return flow {
        source.collect { value ->
            ensureActive()
            emit(value)
        }
    }
}
