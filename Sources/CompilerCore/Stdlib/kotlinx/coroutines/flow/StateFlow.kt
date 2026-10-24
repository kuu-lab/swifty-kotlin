/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/StateFlow.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CompletableDeferred

// MIGRATION-FLOW-003 (KSP-676)
// StateFlow / MutableStateFlow and Flow.stateIn migrated from the dedicated
// runtime handle (kk_mutable_state_flow_create / kk_mutable_state_flow_emit /
// kk_mutable_state_flow_try_emit / kk_state_flow_value / kk_flow_state_in) to
// bundled Kotlin source. MutableStateFlow keeps a single-element replay buffer
// and conflates live collector notifications while preserving equality checks.
//
// KUU-2685: upstream serializes state transitions with `synchronized(this)` so
// compareAndSet is atomic and a collector that registers between a value read
// and an emission still sees it. The port follows the same structure with a
// dedicated SynchronizedObject: every access to `_value` / `activeCollectors` /
// `subscribers` happens under `lock`, and emitConflated dispatches inside the
// same critical section so notifications reach collectors in write order and
// the last-delivered value is always the latest state.

// Each collector owns a FIFO of values and at most one suspended receiver.
// Completing its deferred resumes collection in the collector's own coroutine,
// so downstream aborts and cancellation still unwind through collect's finally.
// The queue/waiter state is guarded by its own lock so that emissions on other
// threads cannot interleave with a receiver's check-then-register sequence
// (KUU-2685): a lost wakeup there would suspend a collector while its value
// sat unread in pendingValues.
internal class HotFlowSubscription<T> {
    private val pendingValues: MutableList<T> = mutableListOf()
    private var waitingCollector: CompletableDeferred<T>? = null
    private val lock = SynchronizedObject()

    fun emit(value: T) {
        val waiting = synchronized(lock) {
            val waiting = waitingCollector
            if (waiting == null) {
                pendingValues.add(value)
            } else {
                waitingCollector = null
            }
            waiting
        }
        waiting?.complete(value)
    }

    fun emitConflated(value: T) {
        val waiting = synchronized(lock) {
            val waiting = waitingCollector
            if (waiting == null) {
                pendingValues.clear()
                pendingValues.add(value)
            } else {
                waitingCollector = null
            }
            waiting
        }
        waiting?.complete(value)
    }

    suspend fun receive(): T {
        val waiting = CompletableDeferred<T>()
        var pending: T? = null
        var hasPending = false
        synchronized(lock) {
            if (pendingValues.isNotEmpty()) {
                pending = pendingValues.removeAt(0)
                hasPending = true
            } else {
                waitingCollector = waiting
            }
        }
        if (hasPending) {
            @Suppress("UNCHECKED_CAST")
            return pending as T
        }
        return waiting.await()
    }

    fun clear() {
        synchronized(lock) {
            pendingValues.clear()
            waitingCollector = null
        }
    }
}

public interface StateFlow<out T> : SharedFlow<T> {
    public val value: T
}

public class MutableStateFlow<T>(initialValue: T) : StateFlow<T>, MutableSharedFlow<T> {
    private var _value: T = initialValue
    private val activeCollectors: MutableList<HotFlowSubscription<T>> = mutableListOf()
    private var subscribers: MutableStateFlow<Int>? = null
    private val lock = SynchronizedObject()

    override val replayCache: List<T>
        get() = listOf(value)

    override var value: T
        get() = synchronized(lock) { _value }
        set(value) {
            synchronized(lock) {
                if (_value != value) {
                    _value = value
                    notifyCollectorsLocked(value)
                }
            }
        }

    override val subscriptionCount: StateFlow<Int>
        get() = synchronized(lock) { subscriptionCounter() }

    // The caller must hold `lock`. Delivering inside the critical section keeps
    // emit order identical to write order, so conflation can drop intermediate
    // values but never leaves a collector with a stale tail.
    private fun notifyCollectorsLocked(value: T) {
        for (collector in activeCollectors) {
            collector.emitConflated(value)
        }
    }

    private fun subscriptionCounter(): MutableStateFlow<Int> {
        val existing = subscribers
        if (existing != null) return existing
        val counter = MutableStateFlow(0)
        subscribers = counter
        return counter
    }

    override fun tryEmit(value: T): Boolean {
        this.value = value
        return true
    }

    public fun compareAndSet(expect: T, update: T): Boolean = synchronized(lock) {
        if (_value != expect) {
            false
        } else if (_value == update) {
            // CAS succeeds without storing so equal values keep their identity.
            true
        } else {
            _value = update
            notifyCollectorsLocked(update)
            true
        }
    }

    override suspend fun emit(value: T) {
        tryEmit(value)
    }

    override fun resetReplayCache() {
        throw UnsupportedOperationException("MutableStateFlow does not support resetReplayCache")
    }

    override suspend fun collect(collector: suspend (T) -> Unit) {
        collectImpl(collector, null)
    }

    internal suspend fun collectWithSharing(
        collector: suspend (T) -> Unit,
        sharing: SnapshotSharingController
    ) {
        collectImpl(collector, sharing)
    }

    private suspend fun collectImpl(
        collector: suspend (T) -> Unit,
        sharing: SnapshotSharingController?
    ) {
        val subscription = HotFlowSubscription<T>()
        // Registration, the first value delivery, and the subscription count
        // form one critical section: an emission cannot slip between them and
        // be missed by this collector.
        val counter = synchronized(lock) {
            activeCollectors.add(subscription)
            subscription.emitConflated(_value)
            subscriptionCounter().also { it.update { count -> count + 1 } }
        }
        var sharingSubscribed = false
        var hasPrevious = false
        var previous: Any? = null
        try {
            if (sharing != null) {
                sharing.subscribe()
                sharingSubscribed = true
            }
            while (true) {
                val next = subscription.receive()
                if (!hasPrevious || previous != next) {
                    hasPrevious = true
                    previous = next
                    collector(next)
                }
            }
        } finally {
            synchronized(lock) {
                activeCollectors.remove(subscription)
                subscription.clear()
                counter.update { it - 1 }
            }
            if (sharingSubscribed) sharing?.unsubscribe()
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
