/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Emitters.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.cancel
import kotlinx.coroutines.channels.close
import kotlinx.coroutines.channels.iterator
import kotlinx.coroutines.channels.hasNext
import kotlinx.coroutines.channels.next
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

public fun <T, R> Flow<T>.transform(action: suspend FlowCollector<R>.(T) -> Unit): Flow<R> {
    val source = this
    return flow {
        val collector = SendingCollector<R> { value -> emit(value) }
        source.collect { value -> action(collector, value) }
    }
}

public fun <T, R> Flow<T>.transformWhile(action: suspend FlowCollector<R>.(T) -> Boolean): Flow<R> {
    val source = this
    return flow {
        val collector = SendingCollector<R> { value -> emit(value) }
        try {
            source.collect { value ->
                if (!action(collector, value)) throw AbortFlowException(collector)
            }
        } catch (e: AbortFlowException) {
            if (e.owner !== collector) throw e
        }
    }
}

public fun <T> Flow<T>.onStart(action: suspend FlowCollector<T>.() -> Unit): Flow<T> {
    val source = this
    return flow {
        val collector = SendingCollector<T> { value -> emit(value) }
        action(collector)
        source.collect { value -> collector.emit(value) }
    }
}

public fun <T> Flow<T>.onCompletion(action: suspend FlowCollector<T>.(cause: Throwable?) -> Unit): Flow<T> {
    val source = this
    return flow {
        val collector = SendingCollector<T> { value -> emit(value) }
        try {
            source.collect { value -> collector.emit(value) }
        } catch (e: Throwable) {
            ThrowingCollector<T>(e).invokeSafely(action, e)
            throw e
        }
        action(collector, null)
    }
}

private suspend fun <T> FlowCollector<T>.invokeSafely(
    action: suspend FlowCollector<T>.(cause: Throwable?) -> Unit,
    cause: Throwable
) {
    try {
        action(this, cause)
    } catch (completion: Throwable) {
        if (completion !== cause) completion.addSuppressed(cause)
        throw completion
    }
}

internal class ThrowingCollector<T>(private val failure: Throwable) : FlowCollector<T> {
    override suspend fun emit(value: T) {
        throw failure
    }
}

// OPTIONAL_CHANNEL means flowOn introduced a channel without specifying its
// capacity. ChannelFlow resolves it to the default buffered capacity when
// collection starts.
internal const val OPTIONAL_CHANNEL_CAPACITY: Int = -3

internal class ChannelFlow<T>(
    internal val upstream: Flow<T>,
    internal val upstreamContext: CoroutineContext,
    internal val capacity: Int,
    internal val onBufferOverflow: BufferOverflow
) : Flow<T> {
    internal suspend fun collectTo(collector: suspend (T) -> Unit) {
        coroutineScope {
            val actualCapacity = if (capacity == OPTIONAL_CHANNEL_CAPACITY) {
                Channel.BUFFERED
            } else {
                capacity
            }
            val channel = Channel<T>(actualCapacity, onBufferOverflow)
            val source = upstream
            val producer = launch(upstreamContext) {
                try {
                    source.collect { value -> channel.send(value) }
                    channel.close()
                } catch (cause: Throwable) {
                    channel.close(cause)
                }
            }

            var completed = false
            try {
                val iterator = channel.iterator()
                while (iterator.hasNext()) {
                    @Suppress("UNCHECKED_CAST")
                    val value = iterator.next() as T
                    collector(value)
                }
                completed = true
            } finally {
                if (!completed) {
                    channel.cancel()
                    producer.cancel()
                }
            }
        }
    }
}

// Adjacent buffer/flowOn operators combine their context and buffer settings
// so collection starts only one producer for the fused segment.
internal fun <T> Flow<T>.fuse(
    context: CoroutineContext = EmptyCoroutineContext,
    capacity: Int = OPTIONAL_CHANNEL_CAPACITY,
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND
): Flow<T> {
    if (context == EmptyCoroutineContext && capacity == OPTIONAL_CHANNEL_CAPACITY &&
        onBufferOverflow == BufferOverflow.SUSPEND
    ) {
        return this
    }

    val previous = if (this is ChannelFlow<*>) {
        @Suppress("UNCHECKED_CAST")
        this as ChannelFlow<T>
    } else {
        null
    }
    if (previous == null) {
        return ChannelFlow(this, context, capacity, onBufferOverflow)
    }

    // The earlier (upstream) context wins when both contexts contain the same key.
    val mergedContext = context + previous.upstreamContext
    val mergedCapacity: Int
    val mergedOverflow: BufferOverflow
    if (onBufferOverflow != BufferOverflow.SUSPEND) {
        // A non-suspending overflow strategy replaces preceding buffer settings.
        mergedCapacity = capacity
        mergedOverflow = onBufferOverflow
    } else {
        mergedCapacity = when {
            previous.capacity == OPTIONAL_CHANNEL_CAPACITY -> capacity
            capacity == OPTIONAL_CHANNEL_CAPACITY -> previous.capacity
            previous.capacity == Channel.BUFFERED -> capacity
            capacity == Channel.BUFFERED -> previous.capacity
            else -> {
                val sum = previous.capacity + capacity
                if (sum >= 0) sum else Channel.UNLIMITED
            }
        }
        mergedOverflow = previous.onBufferOverflow
    }
    return ChannelFlow(
        previous.upstream,
        mergedContext,
        mergedCapacity,
        mergedOverflow
    )
}

public fun <T> Flow<T>.onEmpty(action: suspend FlowCollector<T>.() -> Unit): Flow<T> {
    val source = this
    return flow {
        var empty = true
        source.collect { value ->
            empty = false
            emit(value)
        }
        if (empty) {
            action(AmbientFlowCollector())
        }
    }
}
