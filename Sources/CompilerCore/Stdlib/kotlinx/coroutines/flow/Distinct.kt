/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Distinct.kt>.
 */

package kotlinx.coroutines.flow

public fun <T> Flow<T>.distinctUntilChanged(): Flow<T> =
    distinctUntilChangedBy { it }

@Suppress("UNCHECKED_CAST")
public fun <T> Flow<T>.distinctUntilChanged(areEquivalent: (old: T, new: T) -> Boolean): Flow<T> {
    val source = this
    return flow {
        var seen = false
        var previous: Any? = null
        source.collect { value ->
            if (!seen || !areEquivalent(previous as T, value)) {
                seen = true
                previous = value
                emit(value)
            }
        }
    }
}

public fun <T, K> Flow<T>.distinctUntilChangedBy(keySelector: (T) -> K): Flow<T> {
    val source = this
    return flow {
        var seen = false
        var previous: Any? = null
        source.collect { value ->
            val key = keySelector(value)
            if (!seen || previous != key) {
                seen = true
                previous = key
                emit(value)
            }
        }
    }
}
