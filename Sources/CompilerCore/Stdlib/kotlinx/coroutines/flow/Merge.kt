/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Merge.kt>.
 */

package kotlinx.coroutines.flow

// Latest operators finish each transform sequentially, like flatMapLatest.
public fun <T, R> Flow<T>.mapLatest(transform: suspend (T) -> R): Flow<R> = map(transform)

// KUU-955: callbacks cannot cancel an in-flight transform yet. Keep collection
// streaming so downstream failures and early termination still reach upstream.
public fun <T, R> Flow<T>.transformLatest(transform: suspend FlowCollector<R>.(value: T) -> Unit): Flow<R> =
    this.transform(transform)

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
