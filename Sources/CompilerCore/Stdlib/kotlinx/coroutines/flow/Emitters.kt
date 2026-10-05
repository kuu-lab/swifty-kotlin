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
