/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/operators/Share.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow

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

public fun <T> MutableStateFlow<T>.asSharedFlow(): SharedFlow<T> = ReadonlySharedFlow(this)

// Snapshot flows have no live producer/consumer buffer or dispatcher boundary.
// Like the cold-flow temporal operators, fusion preserves the source instance.
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

public fun <T> StateFlow<T>.distinctUntilChanged(): StateFlow<T> = this

public fun <T> Flow<T>.shareIn(
    scope: CoroutineScope,
    started: SharingStarted,
    replay: Int = 0
): SharedFlow<T> {
    val shared = MutableSharedFlow<T>(replay)
    val sharing = SnapshotSharing(this, scope, started, shared) { shared.resetReplayCache() }
    return SharingSharedFlow(shared, sharing)
}

public fun <T> Flow<T>.stateIn(
    scope: CoroutineScope,
    started: SharingStarted,
    initialValue: T
): StateFlow<T> {
    val state = MutableStateFlow<T>(initialValue)
    val sharing = SnapshotSharing(this, scope, started, state) { state.tryEmit(initialValue) }
    return SharingStateFlow(state, sharing)
}

// Collection subscribes for the duration of one buffered snapshot.
private class SnapshotSharing<T>(
    private val source: Flow<T>,
    private val scope: CoroutineScope,
    private val started: SharingStarted,
    private val collector: FlowCollector<T>,
    private val reset: () -> Unit
) {
    private val subscriptions = SnapshotSubscriptionCount()
    private var collecting = false
    private var launched: Job? = null

    init {
        launched = launchCommands()
    }

    private fun launchCommands(): Job = scope.launch {
        for (command in started.command(subscriptions).toList()) {
            when (command) {
                SharingCommand.START -> {
                    if (!collecting) {
                        collecting = true
                        source.collect(collector)
                    }
                }
                SharingCommand.STOP -> collecting = false
                SharingCommand.STOP_AND_RESET_REPLAY_CACHE -> {
                    collecting = false
                    reset()
                }
            }
        }
    }

    suspend fun subscribe() {
        launched?.join()
        subscriptions.update(subscriptions.value + 1)
        launched = launchCommands()
        launched?.join()
    }

    suspend fun unsubscribe() {
        subscriptions.update(subscriptions.value - 1)
        launched = launchCommands()
        launched?.join()
    }
}

private class SnapshotSubscriptionCount : StateFlow<Int> {
    private var previous: Int = 0
    private var current: Int = 0

    override val value: Int
        get() = current

    override val replayCache: List<Int>
        get() = listOf(current)

    fun update(value: Int) {
        previous = current
        current = value
    }

    override suspend fun collect(collector: suspend (Int) -> Unit) {
        if (previous != current) collector(previous)
        collector(current)
    }
}

private class SharingSharedFlow<T>(
    private val shared: SharedFlow<T>,
    private val sharing: SnapshotSharing<T>
) : SharedFlow<T> {
    override val replayCache: List<T>
        get() = shared.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        sharing.subscribe()
        try {
            shared.collect(collector)
        } finally {
            sharing.unsubscribe()
        }
    }
}

private class SharingStateFlow<T>(
    private val state: StateFlow<T>,
    private val sharing: SnapshotSharing<T>
) : StateFlow<T> {
    override val value: T
        get() = state.value

    override val replayCache: List<T>
        get() = state.replayCache

    override suspend fun collect(collector: suspend (T) -> Unit) {
        sharing.subscribe()
        try {
            state.collect(collector)
        } finally {
            sharing.unsubscribe()
        }
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
