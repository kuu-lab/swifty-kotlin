/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Merge.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.cancel
import kotlinx.coroutines.channels.tryReceive
import kotlinx.coroutines.channels.trySend
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

public fun <T, R> Flow<T>.mapLatest(transform: suspend (T) -> R): Flow<R> {
    val source = this
    return source.transformLatest { value -> emit(transform(value)) }
}

// ChannelFlowTransformLatest shape (KUU-2716), adapted to this runtime's
// scheduling model: transform children emit into a private buffered channel
// instead of calling the downstream collector directly, so an upstream emit
// returns as soon as its child starts, the child's own emit keeps running,
// and downstream failures never reach upstream suspension points. Buffered
// values are drained downstream by the collecting coroutine itself — ambient
// `emit` only ever runs inside the collect lambda (or after collection
// ends), where it binds to the real downstream collector; a separately
// launched drainer would bind to the innermost active collect context and
// feed values back into the upstream lambda (and this runtime schedules
// queued children off-loop concurrently, so no sibling drainer can preserve
// cold ordering anyway).
//
// Drains run when a subsequent upstream value arrives, when a full buffer
// parks a child's send, and once upstream collection finishes, matching the
// JVM observable ordering for cold, hot, overflow, and downstream-failure
// cases. An upstream failure cancels the pending child and discards the
// buffer, matching JVM's produce-cancellation. A transform body failure is
// recorded by the child itself (`childFailure`) because coroutineScope only
// surfaces child failures at scope end; the suspend ABI always parks the
// child once when its suspend call completes thrown, so detection can trail
// one drain — buffered values already delivered before the failure lands may
// still reach downstream where JVM's closed-with-cause channel drops them
// (residual edge tracked as KUU-2724).
public fun <T, R> Flow<T>.transformLatest(
    transform: suspend FlowCollector<R>.(value: T) -> Unit
): Flow<R> {
    val source = this
    return flow {
        coroutineScope {
            val channel = Channel<R>(Channel.BUFFERED)
            var sendBlocked = false
            val collector = SendingCollector<R> { emitted ->
                val sendResult = channel.trySend(emitted)
                if (sendResult.isFailure) {
                    sendBlocked = true
                    channel.send(emitted)
                    sendBlocked = false
                }
            }
            var previous: Job? = null
            var childFailure: Throwable? = null
            try {
                source.collect { value ->
                    val prev = previous
                    val child = launch(start = CoroutineStart.UNDISPATCHED) {
                        prev?.cancel()
                        if (prev?.isCompleted != true) {
                            prev?.join()
                        }
                        try {
                            transform(collector, value)
                        } catch (thrown: Throwable) {
                            if (thrown !is CancellationException) {
                                childFailure = thrown
                            }
                        }
                    }
                    previous = child
                    childFailure?.let { throw it }
                    if (prev != null || sendBlocked) {
                        while (true) {
                            val received = channel.tryReceive()
                            if (!received.isSuccess) break
                            emit(received.getOrThrow())
                        }
                    }
                }
                // Wait out the last child while draining — a plain join could
                // park on a child whose send is blocked by the buffer only
                // this coroutine drains; delay(1) is the cooperative pump
                // that lets the loop run the child's resume turns.
                val lastChild = previous
                while (lastChild != null && !lastChild.isCompleted) {
                    val received = channel.tryReceive()
                    if (received.isSuccess) {
                        emit(received.getOrThrow())
                    } else {
                        delay(1)
                    }
                }
                childFailure?.let { throw it }
                channel.close()
                while (true) {
                    val received = channel.tryReceive()
                    if (!received.isSuccess) break
                    emit(received.getOrThrow())
                }
            } catch (thrown: Throwable) {
                previous?.cancel()
                channel.cancel()
                throw thrown
            }
        }
    }
}

// Upstream reads the `kotlinx.coroutines.flow.defaultConcurrency` system
// property; the bundled stdlib fixes the upstream default of 16.
public const val DEFAULT_CONCURRENCY_PROPERTY_NAME: String = "kotlinx.coroutines.flow.defaultConcurrency"
public const val DEFAULT_CONCURRENCY: Int = 16

public fun <T> Flow<Flow<T>>.flattenConcat(): Flow<T> {
    val source = this
    return flow {
        val collector = SendingCollector<T> { value -> emit(value) }
        source.collect { inner ->
            inner.collect { value -> collector.emit(value) }
        }
    }
}

// Sequential cold-flow model: `merge` collects each flow in order instead of
// merging concurrently (same caveat family as flatMapMerge, KUU-1350).
public fun <T> Iterable<Flow<T>>.merge(): Flow<T> {
    val sources = this
    return flow {
        for (source in sources) {
            source.collect { value -> emit(value) }
        }
    }
}

public fun <T> Flow<Flow<T>>.flattenMerge(concurrency: Int = DEFAULT_CONCURRENCY): Flow<T> {
    require(concurrency > 0) { "Expected positive concurrency level, but had $concurrency" }
    return flattenConcat()
}
