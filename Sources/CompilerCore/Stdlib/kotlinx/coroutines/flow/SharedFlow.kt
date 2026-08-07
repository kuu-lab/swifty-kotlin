/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/SharedFlow.kt>.
 */

package kotlinx.coroutines.flow

// MIGRATION-FLOW-002 (KSP-675)
// SharedFlow / MutableSharedFlow migrated from the dedicated runtime handle
// (kk_mutable_shared_flow_create / kk_mutable_shared_flow_emit /
// kk_mutable_shared_flow_try_emit / kk_shared_flow_collect /
// kk_shared_flow_replay_cache) to Kotlin source: the replay buffer and its
// eviction are plain Kotlin state transitions over a MutableList.
//
// Divergence carried over from the previous runtime implementation: `collect`
// replays the buffered snapshot and returns instead of suspending forever on a
// live subscription. StateFlow keeps its own runtime handle until KSP-676.

public interface SharedFlow<out T> {
    public val replayCache: List<T>

    public suspend fun collect(collector: suspend (T) -> Unit)
}

public class MutableSharedFlow<T>(private val replay: Int) : SharedFlow<T> {
    private val buffer: MutableList<T> = mutableListOf()

    override val replayCache: List<T>
        get() = buffer.toList()

    public fun tryEmit(value: T): Boolean {
        if (replay > 0) {
            buffer.add(value)
            while (buffer.size > replay) {
                buffer.removeAt(0)
            }
        }
        return true
    }

    public suspend fun emit(value: T) {
        tryEmit(value)
    }

    override suspend fun collect(collector: suspend (T) -> Unit) {
        for (value in replayCache) {
            collector(value)
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
