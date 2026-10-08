/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/SharedFlow.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.awaitCancellation

// MIGRATION-FLOW-002 (KSP-675)
// SharedFlow / MutableSharedFlow migrated from the dedicated runtime handle
// (kk_mutable_shared_flow_create / kk_mutable_shared_flow_emit /
// kk_mutable_shared_flow_try_emit / kk_shared_flow_collect /
// kk_shared_flow_replay_cache) to Kotlin source: the replay buffer and its
// eviction are plain Kotlin state transitions over a MutableList.
//
// Divergence carried over from the previous runtime implementation: `collect`
// replays the buffered snapshot but does not forward later emissions. It stays
// suspended until cancellation so subscriptionCount reflects the collector's
// lifetime. StateFlow is now Kotlin source as well (StateFlow.kt, KSP-676).

public interface SharedFlow<out T> : Flow<T> {
    public val replayCache: List<T>

    public suspend fun collect(collector: suspend (T) -> Unit)
}

// Keep the mutable contract separate from its snapshot implementation so that
// MutableStateFlow can also implement it, as in kotlinx.coroutines.
public interface MutableSharedFlow<T> : SharedFlow<T>, FlowCollector<T> {
    public val subscriptionCount: StateFlow<Int>

    public fun tryEmit(value: T): Boolean

    public fun resetReplayCache()
}

public fun <T> MutableSharedFlow(
    replay: Int = 0,
    extraBufferCapacity: Int = 0,
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND
): MutableSharedFlow<T> = SnapshotMutableSharedFlow<T>(replay, extraBufferCapacity, onBufferOverflow)

private class SnapshotMutableSharedFlow<T>(
    private val replay: Int,
    extraBufferCapacity: Int,
    onBufferOverflow: BufferOverflow
) : MutableSharedFlow<T> {
    private val buffer: MutableList<T> = mutableListOf()
    private var subscribers: MutableStateFlow<Int>? = null

    init {
        require(replay >= 0) { "replay cannot be negative" }
        require(extraBufferCapacity >= 0) { "extraBufferCapacity cannot be negative" }
        require(onBufferOverflow == BufferOverflow.SUSPEND || replay > 0 || extraBufferCapacity > 0) {
            "non-default onBufferOverflow requires positive replay or extraBufferCapacity"
        }
    }

    override val subscriptionCount: StateFlow<Int>
        get() = subscriptionCounter()

    private fun subscriptionCounter(): MutableStateFlow<Int> {
        val existing = subscribers
        if (existing != null) return existing
        val counter = MutableStateFlow(0)
        subscribers = counter
        return counter
    }

    override val replayCache: List<T>
        get() = buffer.toList()

    override fun tryEmit(value: T): Boolean {
        if (replay > 0) {
            buffer.add(value)
            while (buffer.size > replay) {
                buffer.removeAt(0)
            }
        }
        return true
    }

    override suspend fun emit(value: T) {
        tryEmit(value)
    }

    override fun resetReplayCache() {
        buffer.clear()
    }

    override suspend fun collect(collector: suspend (T) -> Unit) {
        val snapshot = replayCache
        val counter = subscriptionCounter()
        counter.value = counter.value + 1
        try {
            for (value in snapshot) {
                collector(value)
            }
            awaitCancellation()
        } finally {
            counter.value = counter.value - 1
        }
    }
}

public suspend fun <T> Flow<T>.shareIn(replay: Int): SharedFlow<T> {
    val shared = MutableSharedFlow<T>(replay)
    val source = this
    source.collect { value ->
        @Suppress("UNCHECKED_CAST")
        shared.tryEmit(value as T)
    }
    return shared
}
