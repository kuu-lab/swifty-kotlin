/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Merge.kt>.
 */

package kotlinx.coroutines.flow

public interface FlowCollector<in T> {
    public suspend fun emit(value: T)
}

private class BufferedFlowCollector<T>(val values: MutableList<T>) : FlowCollector<T> {
    override suspend fun emit(value: T) {
        values.add(value)
    }
}

// Latest operators finish each transform sequentially, like flatMapLatest.
public fun <T, R> Flow<T>.mapLatest(transform: suspend (T) -> R): Flow<R> = map(transform)

public fun <T, R> Flow<T>.transformLatest(transform: suspend FlowCollector<R>.(value: T) -> Unit): Flow<R> {
    val source = this
    return flow {
        val values = mutableListOf<R>()
        val collector = BufferedFlowCollector<R>(values)
        for (value in source.toList()) {
            transform(collector, value)
            for (result in values) emit(result)
            values.clear()
        }
    }
}
