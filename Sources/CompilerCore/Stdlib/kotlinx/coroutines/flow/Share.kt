/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Share.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.channels.BufferOverflow

private class ReadonlySharedFlow<T>(private val source: SharedFlow<T>) : SharedFlow<T> {
    override val replayCache: List<T>
        get() = source.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        source.collect(collector)
    }
}

private class ReadonlyStateFlow<T>(private val source: StateFlow<T>) : StateFlow<T> {
    override val value: T
        get() = source.value

    override val replayCache: List<T>
        get() = source.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        source.collect(collector)
    }
}

public fun <T> MutableSharedFlow<T>.asSharedFlow(): SharedFlow<T> = ReadonlySharedFlow(this)

public fun <T> MutableStateFlow<T>.asStateFlow(): StateFlow<T> = ReadonlyStateFlow(this)

public fun <T> MutableStateFlow<T>.asSharedFlow(): SharedFlow<T> = ReadonlySharedFlow(this)

// Snapshot flows have no live producer/consumer buffer or dispatcher boundary.
// Like the cold-flow temporal operators, fusion preserves the source instance.
public fun <T> SharedFlow<T>.buffer(
    capacity: Int = -2,
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND
): SharedFlow<T> {
    require(capacity >= 0 || capacity == -2 || capacity == -1) { "Invalid buffer capacity" }
    require(capacity != -1 || onBufferOverflow == BufferOverflow.SUSPEND) {
        "CONFLATED capacity cannot be used with non-default onBufferOverflow"
    }
    return this
}

public fun <T> SharedFlow<T>.flowOn(context: CoroutineContext): SharedFlow<T> = this

public fun <T> SharedFlow<T>.cancellable(): SharedFlow<T> = this

public fun <T> SharedFlow<T>.conflate(): SharedFlow<T> = this

public fun <T> StateFlow<T>.distinctUntilChanged(): StateFlow<T> = this
