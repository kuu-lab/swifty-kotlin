/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/SharedFlow.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.CompletableDeferred

// MIGRATION-FLOW-002 (KSP-675)
// SharedFlow / MutableSharedFlow migrated from the dedicated runtime handle
// (kk_mutable_shared_flow_create / kk_mutable_shared_flow_emit /
// kk_mutable_shared_flow_try_emit / kk_shared_flow_collect /
// kk_shared_flow_replay_cache) to Kotlin source: the replay buffer and its
// eviction are plain Kotlin state transitions over a MutableList.
//
// Collectors subscribe through per-collector queues. Replay is delivered before
// each collector starts receiving live emissions, and collection remains
// suspended until cancellation or a downstream terminal operator.
// StateFlow is now Kotlin source as well (StateFlow.kt, KSP-676).

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

// Each collector owns a FIFO of values and at most one suspended receiver.
// Completing its deferred resumes collection in the collector's own coroutine,
// so downstream aborts and cancellation still unwind through collect's finally.
internal class HotFlowSubscription<T> {
    private val pendingValues: MutableList<T> = mutableListOf()
    private var waitingCollector: CompletableDeferred<T>? = null

    fun emit(value: T) {
        val waiting = waitingCollector
        if (waiting == null) {
            pendingValues.add(value)
        } else {
            waitingCollector = null
            waiting.complete(value)
        }
    }

    fun emitConflated(value: T) {
        val waiting = waitingCollector
        if (waiting == null) {
            pendingValues.clear()
            pendingValues.add(value)
        } else {
            waitingCollector = null
            waiting.complete(value)
        }
    }

    suspend fun receive(): T {
        if (pendingValues.isNotEmpty()) return pendingValues.removeAt(0)

        val waiting = CompletableDeferred<T>()
        waitingCollector = waiting
        if (pendingValues.isNotEmpty()) {
            waitingCollector = null
            waiting.complete(pendingValues.removeAt(0))
        }
        return waiting.await()
    }

    fun clear() {
        pendingValues.clear()
        waitingCollector = null
    }
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
    private val activeCollectors: MutableList<HotFlowSubscription<T>> = mutableListOf()
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
        for (collector in activeCollectors.toList()) {
            collector.emit(value)
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
        val subscription = HotFlowSubscription<T>()
        val snapshot = replayCache
        val counter = subscriptionCounter()
        activeCollectors.add(subscription)
        counter.value = counter.value + 1
        try {
            for (value in snapshot) {
                collector(value)
            }
            while (true) {
                collector(subscription.receive())
            }
        } finally {
            activeCollectors.remove(subscription)
            subscription.clear()
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
