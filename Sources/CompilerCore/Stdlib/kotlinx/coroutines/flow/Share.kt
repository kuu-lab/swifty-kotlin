/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Share.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.coroutines.CoroutineContext
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.launch

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

// flowOn, cancellable, and rendezvous buffer are identity operators for
// SharedFlow. KSwiftK also preserves identity for configurable buffers and
// conflate because it does not yet model their downstream channel semantics;
// that compatibility limit is pinned by the snapshot API regression case.
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

// StateFlow collection already suppresses equal consecutive values.
public fun <T> StateFlow<T>.distinctUntilChanged(): StateFlow<T> = this

public fun <T> Flow<T>.shareIn(
    scope: CoroutineScope,
    started: SharingStarted,
    replay: Int = 0
): SharedFlow<T> {
    val shared = newSharedFlowForSharing<T>(replay)
    val sharing = SnapshotSharing<T>(this, scope, started, shared) {
        shared.resetReplayCache()
    }
    return SharingSharedFlow<T>(shared, sharing.controller)
}

public fun <T> Flow<T>.stateIn(
    scope: CoroutineScope,
    started: SharingStarted,
    initialValue: T
): StateFlow<T> {
    val state = MutableStateFlow<T>(initialValue)
    val sharing = SnapshotSharing<T>(this, scope, started, state) {
        state.tryEmit(initialValue)
    }
    return SharingStateFlow<T>(state, sharing.controller)
}

// A scope-owned controller applies the reactive sharing command stream.
private class SnapshotSharing<T>(
    source: Flow<T>,
    scope: CoroutineScope,
    started: SharingStarted,
    collector: FlowCollector<T>,
    reset: () -> Unit
) {
    private val controllerDispatcher: CoroutineDispatcher =
        scope.coroutineContext[CoroutineDispatcher] ?: Dispatchers.Default

    internal val controller: SnapshotSharingController = SnapshotSharingController(
        scope,
        started,
        { source.collect(collector) },
        reset
    )

    init {
        val controller = this.controller
        scope.launch(controllerDispatcher, start = CoroutineStart.DEFAULT) {
            controller.collectCommands()
        }
    }

}

internal class SnapshotSharingController(
    private val scope: CoroutineScope,
    private val started: SharingStarted,
    private val collectUpstream: suspend () -> Unit,
    private val reset: () -> Unit
) {
    private val subscriptions = MutableStateFlow(0)
    private val lock = SynchronizedObject()
    private var upstreamJob: Job? = null

    suspend fun collectCommands() {
        started.command(subscriptions).distinctUntilChanged().collect { command ->
            when (command) {
                SharingCommand.START -> startUpstream()
                SharingCommand.STOP -> stopUpstream()
                SharingCommand.STOP_AND_RESET_REPLAY_CACHE -> {
                    stopUpstream()
                    reset()
                }
            }
        }
        // Eagerly emits one command; keep its scope-owned sharing controller alive afterward.
        if (started.isEagerly()) awaitCancellation()
    }

    fun subscribe() {
        subscriptions.update { it + 1 }
    }

    fun unsubscribe() {
        subscriptions.update { it - 1 }
    }

    private fun startUpstream() {
        synchronized(lock) {
            if (upstreamJob?.isActive == true) return
        }
        val upstreamAction = collectUpstream
        val job = scope.launch(start = CoroutineStart.LAZY) {
            upstreamAction()
        }
        synchronized(lock) {
            if (upstreamJob?.isActive == true) {
                job.cancel()
                return
            }
            upstreamJob = job
        }
        job.start()
    }

    private suspend fun stopUpstream() {
        val current = synchronized(lock) {
            val current = upstreamJob
            upstreamJob = null
            current
        }
        if (current != null) current.cancelAndJoin()
    }
}

private class SharingSharedFlow<T>(
    private val shared: SharedFlowImpl<T>,
    private val sharing: SnapshotSharingController
) : SharedFlow<T> {
    override val replayCache: List<T>
        get() = shared.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        shared.collectWithSharing(collector, sharing)
    }
}

private class SharingStateFlow<T>(
    private val state: MutableStateFlow<T>,
    private val sharing: SnapshotSharingController
) : StateFlow<T> {
    override val value: T
        get() = state.value

    override val replayCache: List<T>
        get() = state.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        state.collectWithSharing(collector, sharing)
    }
}

public fun <T> SharedFlow<T>.onSubscription(action: suspend FlowCollector<T>.() -> Unit): SharedFlow<T> =
    SubscribedSharedFlow(this, action)

private class SubscribedSharedFlow<T>(
    private val source: SharedFlow<T>,
    private val action: suspend FlowCollector<T>.() -> Unit
) : SharedFlow<T> {
    override val replayCache: List<T>
        get() = source.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        runActions(collector)
        collectSource(collector)
    }

    @Suppress("UNCHECKED_CAST")
    suspend fun runActions(collector: suspend (T) -> Unit) {
        if (source is SubscribedSharedFlow<*>) {
            (source as SubscribedSharedFlow<T>).runActions(collector)
        }
        val forwarding = SubscriptionCollector(collector)
        action(forwarding)
    }

    @Suppress("UNCHECKED_CAST")
    suspend fun collectSource(collector: suspend (T) -> Unit) {
        if (source is SubscribedSharedFlow<*>) {
            (source as SubscribedSharedFlow<T>).collectSource(collector)
        } else {
            source.collect(collector)
        }
    }
}

private class SubscriptionCollector<T>(private val collector: suspend (T) -> Unit) : FlowCollector<T> {
    override suspend fun emit(value: T) {
        collector(value)
    }
}
