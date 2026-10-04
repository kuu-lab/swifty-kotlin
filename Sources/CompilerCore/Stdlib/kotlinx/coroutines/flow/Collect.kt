/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/terminal/Collect.kt>.
 */

package kotlinx.coroutines.flow

public suspend fun <T> Flow<T>.collectIndexed(action: suspend (index: Int, value: T) -> Unit) {
    var index = 0
    this.collect { value ->
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        action(index, value)
        index += 1
    }
}

// The retained cold-flow core delivers collector calls synchronously.
public suspend fun <T> Flow<T>.collectLatest(action: suspend (value: T) -> Unit) {
    this.collect { value -> action(value) }
}

public suspend fun <T> FlowCollector<T>.emitAll(flow: Flow<T>) {
    val collector = this
    flow.collect { value -> collector.emit(value) }
}

// flow { } currently uses an ambient collector rather than a receiver parameter.
public suspend fun <T> emitAll(flow: Flow<T>) {
    flow.collect { value -> emitToCurrentFlow(value) }
}

internal suspend fun <T> emitToCurrentFlow(value: T) {
    emit(value)
}

private class FlowAbortException : kotlinx.coroutines.CancellationException("Flow collection was aborted.")

internal suspend fun <T> Flow<T>.collectWhile(predicate: suspend (T) -> Boolean) {
    val abort = FlowAbortException()
    try {
        this.collect { value ->
            if (!predicate(value)) throw abort
        }
    } catch (e: FlowAbortException) {
        if (e !== abort) throw e
    }
}
