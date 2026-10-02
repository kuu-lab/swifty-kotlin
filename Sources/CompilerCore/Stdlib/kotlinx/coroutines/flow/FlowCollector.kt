/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/FlowCollector.kt>.
 */

package kotlinx.coroutines.flow

public fun interface FlowCollector<in T> {
    public suspend fun emit(value: T)
}

internal class SendingCollector<T>(private val send: suspend (T) -> Unit) : FlowCollector<T> {
    override suspend fun emit(value: T) {
        send(value)
    }
}

internal class AbortFlowException(val owner: Any) : kotlinx.coroutines.CancellationException("Flow collection aborted")
