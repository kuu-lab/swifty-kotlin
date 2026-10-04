/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Emitters.kt>.
 */

package kotlinx.coroutines.flow

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

// KUU-955: suspend function-value callbacks currently run to completion, so
// the cold-flow core cannot cancel an in-flight transform on the next value.
public fun <T, R> Flow<T>.transformLatest(action: suspend FlowCollector<R>.(T) -> Unit): Flow<R> =
    transform(action)

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

public fun <T> SharedFlow<T>.onSubscription(action: suspend FlowCollector<T>.() -> Unit): SharedFlow<T> =
    SubscribedSharedFlow(this, action)

internal class SubscribedSharedFlow<T>(
    private val source: SharedFlow<T>,
    private val action: suspend FlowCollector<T>.() -> Unit
) : SharedFlow<T> {
    override val replayCache: List<T>
        get() = source.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        val sending = SendingCollector<T>(collector)
        action(sending)
        source.collect { value -> sending.emit(value) }
    }
}

// Skeleton for fusion on the sequential cold-flow core: context and buffering
// do not introduce concurrent producers yet.
internal fun <T> Flow<T>.fuse(
    context: kotlin.coroutines.CoroutineContext = kotlin.coroutines.EmptyCoroutineContext,
    capacity: Int = -3
): Flow<T> = this

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
