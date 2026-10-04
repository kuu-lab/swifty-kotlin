/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Emitters.kt>.
 */

package kotlinx.coroutines.flow

public fun <T> Flow<T>.onEmpty(action: suspend FlowCollector<T>.() -> Unit): Flow<T> {
    val source = this
    return flow {
        var empty = true
        source.collect { value ->
            empty = false
            emit(value)
        }
        if (empty) {
            action(AmbientFlowCollector())
        }
    }
}
