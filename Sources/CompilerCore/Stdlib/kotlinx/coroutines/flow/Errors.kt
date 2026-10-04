/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Errors.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive

internal class ExceptionTrackingCollector<T>(private val downstream: FlowCollector<T>) : FlowCollector<T> {
    var failure: Throwable? = null

    override suspend fun emit(value: T) {
        try {
            downstream.emit(value)
        } catch (e: Throwable) {
            failure = e
            throw e
        }
    }
}

private suspend fun <T> Flow<T>.collectUpstreamFailure(collector: ExceptionTrackingCollector<T>): Throwable? {
    val source = this
    try {
        source.collect { value -> collector.emit(value) }
    } catch (e: Throwable) {
        val downstream = collector.failure
        if (e === downstream || !currentCoroutineContext().isActive) throw e
        val downstreamCause = downstream ?: return e
        val upstream: Throwable = e
        if (e is CancellationException) {
            downstreamCause.addSuppressed(upstream)
            throw downstreamCause
        }
        e.addSuppressed(downstreamCause)
        throw e
    }
    return null
}

public fun <T> Flow<T>.catch(action: suspend FlowCollector<T>.(cause: Throwable) -> Unit): Flow<T> {
    val source = this
    return flow {
        val downstream = SendingCollector<T> { value -> emit(value) }
        val failure = source.collectUpstreamFailure(ExceptionTrackingCollector(downstream))
        if (failure != null) action(downstream, failure)
    }
}

public fun <T> Flow<T>.retry(
    retries: Long = Long.MAX_VALUE,
    predicate: suspend (cause: Throwable) -> Boolean = { true }
): Flow<T> {
    require(retries > 0L) { "Retry count must be positive" }
    return retryWhen { cause, attempt -> attempt < retries && predicate(cause) }
}

public fun <T> Flow<T>.retryWhen(
    predicate: suspend FlowCollector<T>.(cause: Throwable, attempt: Long) -> Boolean
): Flow<T> {
    val source = this
    return flow {
        var attempt = 0L
        val collector = SendingCollector<T> { value -> emit(value) }
        val tracking = ExceptionTrackingCollector(collector)
        while (true) {
            val failure = source.collectUpstreamFailure(tracking) ?: break
            if (!predicate(collector, failure, attempt)) throw failure
            attempt += 1L
        }
    }
}
