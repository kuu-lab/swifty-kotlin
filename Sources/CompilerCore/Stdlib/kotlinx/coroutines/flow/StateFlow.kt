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
// and exposes a finite snapshot collect rather than a live subscription.

public interface StateFlow<out T> : SharedFlow<T> {
    public val value: T
}

public class MutableStateFlow<T>(initialValue: T) : StateFlow<T>, FlowCollector<T> {
    private var _value: T = initialValue
    private var subscribers: MutableStateFlow<Int>? = null

    override val replayCache: List<T>
        get() = listOf(_value)

    override var value: T
        get() = _value
        set(value) {
            if (_value != value) _value = value
        }

    public val subscriptionCount: StateFlow<Int>
        get() = subscriptionCounter()

    private fun subscriptionCounter(): MutableStateFlow<Int> {
        val existing = subscribers
        if (existing != null) return existing
        val counter = MutableStateFlow(0)
        subscribers = counter
        return counter
    }

    public fun tryEmit(value: T): Boolean {
        this.value = value
        return true
    }

    public fun compareAndSet(expect: T, update: T): Boolean {
        if (_value != expect) return false
        value = update
        return true
    }

    override suspend fun emit(value: T) {
        tryEmit(value)
    }

    public fun resetReplayCache() {
        throw UnsupportedOperationException("MutableStateFlow does not support resetReplayCache")
    }

    override suspend fun collect(collector: suspend (T) -> Unit) {
        val snapshot = value
        val counter = subscriptionCounter()
        counter.value = counter.value + 1
        try {
            collector(snapshot)
        } finally {
            counter.value = counter.value - 1
        }
    }
}

public fun <T> MutableStateFlow<T>.update(function: (T) -> T) {
    while (true) {
        val previous = value
        if (compareAndSet(previous, function(previous))) return
    }
}

public fun <T> MutableStateFlow<T>.setValue(value: T) {
    this.value = value
}

public fun <T> MutableStateFlow<T>.getAndUpdate(function: (T) -> T): T {
    while (true) {
        val previous = value
        if (compareAndSet(previous, function(previous))) return previous
    }
}

public fun <T> MutableStateFlow<T>.updateAndGet(function: (T) -> T): T {
    while (true) {
        val previous = value
        val next = function(previous)
        if (compareAndSet(previous, next)) return next
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
