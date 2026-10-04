/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/StateFlow.kt>.
 */

package kotlinx.coroutines.flow

// MIGRATION-FLOW-003 (KSP-676)
// StateFlow / MutableStateFlow and Flow.stateIn migrated from the dedicated
// runtime handle (kk_mutable_state_flow_create / kk_mutable_state_flow_emit /
// kk_mutable_state_flow_try_emit / kk_state_flow_value / kk_flow_state_in) to
// bundled Kotlin source. MutableStateFlow keeps a single-element replay buffer
// over a MutableList and exposes value / replayCache / collect / tryEmit / emit.

public interface StateFlow<out T> {
    public val value: T
    public val replayCache: List<T>
    public suspend fun collect(collector: suspend (T) -> Unit)
}

public class MutableStateFlow<T>(initialValue: T) : StateFlow<T> {
    private var _value: T = initialValue
    private val _buffer: MutableList<T> = mutableListOf(initialValue)

    override val replayCache: List<T>
        get() = _buffer.toList()

    override val value: T
        get() = _value

    public fun tryEmit(value: T): Boolean {
        _value = value
        _buffer.clear()
        _buffer.add(value)
        return true
    }

    public fun setValue(value: T) {
        tryEmit(value)
    }

    public suspend fun emit(value: T) {
        tryEmit(value)
    }

    override suspend fun collect(collector: suspend (T) -> Unit) {
        for (value in _buffer) {
            collector(value)
        }
    }
}

public suspend fun <T> Flow<T>.stateIn(initialValue: T): StateFlow<T> {
    val state = MutableStateFlow<T>(initialValue)
    val source = this
    source.collect { value ->
        @Suppress("UNCHECKED_CAST")
        state.tryEmit(value as T)
    }
    return state
}
