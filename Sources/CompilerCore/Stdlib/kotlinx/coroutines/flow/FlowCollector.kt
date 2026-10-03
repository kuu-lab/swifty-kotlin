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

internal class AmbientFlowCollector : FlowCollector<Any?> {
    override suspend fun emit(value: Any?) {
        emitToCurrentFlow(value)
    }
}
