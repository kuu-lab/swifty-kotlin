/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Transform.kt>.
 */

package kotlinx.coroutines.flow

public fun <T, R> Flow<T>.scan(initial: R, operation: suspend (R, T) -> R): Flow<R> =
    runningFold(initial, operation)

public fun <T, R> Flow<T>.runningFold(initial: R, operation: suspend (R, T) -> R): Flow<R> {
    val source = this
    return flow {
        var accumulator = initial
        emit(accumulator)
        source.collect { value ->
            accumulator = operation(accumulator, value)
            emit(accumulator)
        }
    }
}

public fun <T> Flow<T>.runningReduce(operation: suspend (T, T) -> T): Flow<T> {
    val source = this
    return flow {
        var found = false
        var accumulator: Any? = null
        source.collect { value ->
            if (!found) {
                accumulator = value
                found = true
            } else {
                @Suppress("UNCHECKED_CAST")
                accumulator = operation(accumulator as T, value)
            }
            @Suppress("UNCHECKED_CAST")
            emit(accumulator as T)
        }
    }
}
