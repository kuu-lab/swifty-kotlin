/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Delay.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.inWholeMilliseconds
import kotlin.time.toDuration
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.InternalCoroutinesApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.cancel
import kotlinx.coroutines.channels.produce
import kotlinx.coroutines.selects.select

public fun <T> Flow<T>.drop(count: Int): Flow<T> {
    require(count >= 0) { "Drop count should be non-negative, but had $count" }
    val source = this
    return flow {
        var skipped = 0
        source.collect { value ->
            if (skipped < count) {
                skipped += 1
            } else {
                emit(value)
            }
        }
    }
}

@FlowPreview
@OptIn(ExperimentalCoroutinesApi::class, InternalCoroutinesApi::class)
@Suppress("UNCHECKED_CAST")
public fun <T> Flow<T>.sample(periodMillis: Long): Flow<T> {
    require(periodMillis > 0L) { "Sample period should be positive" }
    val source = this
    return flow {
        coroutineScope {
            val sampleJob = currentCoroutineContext().job
            val values = produce<T>(capacity = Channel.CONFLATED) {
                // Upstream scopedFlow propagates a producer's cancellation.
                // Observe cancellation start so suspended downstream cleanup
                // can run before the producer's finally block finishes.
                val registration = currentCoroutineContext().job.invokeOnCompletion(onCancelling = true) { cause ->
                    if (cause is CancellationException) sampleJob.cancel(cause)
                }
                try { source.collect { send(it) } }
                catch (failure: Throwable) {
                    if (failure is CancellationException) sampleJob.cancel(failure)
                    throw failure
                }
                finally { registration.dispose() }
            }
            val ticks = produce<Unit>(capacity = 0) {
                delay(periodMillis)
                while (true) {
                    send(Unit)
                    delay(periodMillis)
                }
            }
            var open = true
            var pending = false
            var last: T? = null
            while (open) {
                select<Unit> {
                    values.onReceiveCatching { result ->
                        if (result.isSuccess) {
                            last = result.getOrNull()
                            pending = true
                        } else {
                            val failure = result.exceptionOrNull()
                            if (failure != null) throw failure
                            open = false
                            // Normal completion drops the pending tail. Stop
                            // the ticker Job even when its delay is enormous.
                            ticks.cancel()
                        }
                    }
                    ticks.onReceive {
                        if (pending) {
                            pending = false
                            val value = last as T
                            last = null
                            emit(value)
                        }
                    }
                }
            }
        }
    }
}

@FlowPreview
@OptIn(FlowPreview::class)
public fun <T> Flow<T>.sample(period: Duration): Flow<T> {
    require(period > 0L.toDuration(DurationUnit.MILLISECONDS)) { "Sample period should be positive" }
    val millis = period.inWholeMilliseconds
    val rounded = if (millis == Long.MAX_VALUE) millis
        else if (period > millis.toDuration(DurationUnit.MILLISECONDS)) millis + 1L
        else millis
    return sample(rounded)
}

public fun <T> Flow<T>.timeout(timeout: Duration): Flow<T> {
    val source = this
    return flow {
        if (timeout <= Duration.ZERO) {
            throw TimeoutCancellationException("Timed out immediately")
        }
        val wholeMillis = timeout.inWholeMilliseconds
        val timeoutMillis = if (wholeMillis == Long.MAX_VALUE) wholeMillis
            else if (timeout > wholeMillis.toDuration(DurationUnit.MILLISECONDS)) wholeMillis + 1L
            else wholeMillis

        coroutineScope {
            val values = Channel<T>(Channel.BUFFERED)
            val upstream = launch {
                try {
                    source.collect { value -> values.send(value) }
                    values.close()
                } catch (failure: Throwable) {
                    values.close(failure)
                    throw failure
                }
            }

            var timeoutJob: Job? = null

            try {
                var open = true
                timeoutJob = if (timeoutMillis == Long.MAX_VALUE) null else launch {
                    delay(timeoutMillis)
                }
                while (open) {
                    val timer = timeoutJob
                    select<Unit> {
                        values.onReceiveCatching { result ->
                            if (result.isSuccess) {
                                timeoutJob?.cancel()
                                emit(result.getOrThrow())
                                timeoutJob = if (timeoutMillis == Long.MAX_VALUE) null else launch {
                                    delay(timeoutMillis)
                                }
                            } else {
                                val failure = result.exceptionOrNull()
                                if (failure != null) throw failure
                                timeoutJob?.cancel()
                                timeoutJob = null
                                open = false
                            }
                        }
                        if (timer != null) {
                            timer.onJoin {
                                throw TimeoutCancellationException("Timed out waiting for $timeout")
                            }
                        }
                    }
                }
            } finally {
                timeoutJob?.cancel()
                upstream.cancel()
                values.cancel()
            }
        }
    }
}
