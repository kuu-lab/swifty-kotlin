/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Merge.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

// Latest operators finish each transform sequentially, like flatMapLatest.
public fun <T, R> Flow<T>.mapLatest(transform: suspend (T) -> R): Flow<R> = map(transform)

// Each upstream value cancels the previous transform before starting the next.
public fun <T, R> Flow<T>.transformLatest(
    transform: suspend FlowCollector<R>.(value: T) -> Unit
): Flow<R> {
    val source = this
    return flow {
        val collector = SendingCollector<R> { value -> emit(value) }
        coroutineScope {
            var previous: Job? = null
            source.collect { value ->
                previous?.cancel()
                previous?.join()
                previous = launch(start = CoroutineStart.UNDISPATCHED) {
                    transform(collector, value)
                }
            }
            previous?.join()
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
