/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/SharedFlow.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine

// MIGRATION-FLOW-002 (KSP-675, KUU-2684)
// SharedFlow / MutableSharedFlow migrated from the dedicated runtime handle
// (kk_mutable_shared_flow_create / kk_mutable_shared_flow_emit /
// kk_mutable_shared_flow_try_emit / kk_shared_flow_collect /
// kk_shared_flow_replay_cache) to Kotlin source. The buffer/index machinery is
// a straight port of upstream SharedFlowImpl: a single circular buffer is
// shared between replay storage, live emissions for lagging subscribers, and
// queued emitters, so `extraBufferCapacity` and the `onBufferOverflow` policy
// exercise the same state transitions as kotlinx.coroutines.
//
// Each collector is a slot holding the index of the next value it must take;
// `minCollectorIndex` tracks the slowest subscriber and bounds the buffer head.
// Emitters that cannot place a value (SUSPEND with a full buffer) enqueue an
// `Emitter` cell and suspend on a CancellableContinuation; collector progress
// or cancellation frees buffer space and resumes queued emitters through
// `updateCollectorIndexLocked`.
//
// Upstream guards every state mutation with `synchronized(this)` and resumes
// continuations outside the lock; the port keeps the same "mutate first,
// resume afterwards" ordering, which matters because resumed coroutines must
// never observe a half-updated buffer.

public interface SharedFlow<out T> : Flow<T> {
    public val replayCache: List<T>

    public suspend fun collect(collector: suspend (T) -> Unit)
}

// Keep the mutable contract separate from its implementation so that
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
): MutableSharedFlow<T> = createSharedFlowImpl(replay, extraBufferCapacity, onBufferOverflow)

internal fun <T> newSharedFlowForSharing(replay: Int): SharedFlowImpl<T> =
    createSharedFlowImpl(replay, maxOf(0, DEFAULT_SHARING_BUFFER_CAPACITY - replay), BufferOverflow.SUSPEND)

// shareIn uses the default buffered channel capacity, with replay taking precedence.
private const val DEFAULT_SHARING_BUFFER_CAPACITY = 64

private fun <T> createSharedFlowImpl(
    replay: Int,
    extraBufferCapacity: Int,
    onBufferOverflow: BufferOverflow
): SharedFlowImpl<T> {
    require(replay >= 0) { "replay cannot be negative, but was $replay" }
    require(extraBufferCapacity >= 0) { "extraBufferCapacity cannot be negative, but was $extraBufferCapacity" }
    require(replay > 0 || extraBufferCapacity > 0 || onBufferOverflow == BufferOverflow.SUSPEND) {
        "replay or extraBufferCapacity must be positive with non-default onBufferOverflow strategy $onBufferOverflow"
    }
    val bufferCapacity0 = replay + extraBufferCapacity
    val bufferCapacity = if (bufferCapacity0 < 0) Int.MAX_VALUE else bufferCapacity0 // coerce to MAX_VALUE on overflow
    return SharedFlowImpl(replay, bufferCapacity, onBufferOverflow)
}

// Marker placed in buffer cells that held a resumed or cancelled emitter,
// matching upstream's `NO_VALUE` symbol.
private object NoValue

// An emitter suspended inside `emit`; it occupies a buffer cell in the queue
// region (past `bufferEndIndex`) until a collector advances far enough to make
// room for its value.
private class SharedFlowEmitter(
    val index: Long,
    val value: Any?,
    val cont: CancellableContinuation<Unit>
)

private class SharedFlowSlot {
    var index = -1L // current "to-be-emitted" index, -1 means the slot is free now
    var cont: CancellableContinuation<Unit>? = null // collector waiting for new value
}

internal class SharedFlowImpl<T>(
    private val replay: Int,
    private val bufferCapacity: Int,
    private val onBufferOverflow: BufferOverflow
) : MutableSharedFlow<T> {
    /*
        Logical structure of the buffer (same invariants as upstream):

                  buffered values
             /-----------------------\
                          replayCache      queued emitters
                          /----------\/----------------------\
         +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
         |   | 1 | 2 | 3 | 4 | 5 | 6 | E | E | E | E | E | E |   |   |   |
         +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
               ^           ^           ^                      ^
               |           |           |                      |
              head         |      head + bufferSize     head + totalSize
               |           |           |
     index of the slowest  |    index of the fastest
      possible collector   |     possible collector
               |           |
               |     replayIndex == new collector's index
               \---------------------- /
          range of possible minCollectorIndex

          head == minOf(minCollectorIndex, replayIndex) // by definition
          totalSize == bufferSize + queueSize // by definition

       INVARIANTS:
          minCollectorIndex = slots.minOf { it.index } ?: (head + bufferSize)
          replayIndex <= head + bufferSize
    */

    // Stored state
    private val lock = SynchronizedObject()
    private var buffer: Array<Any?>? = null // allocated when needed, allocated size always power of two
    private var replayIndex = 0L // minimal index from which new collector gets values
    private var minCollectorIndex = 0L // minimal index of active collectors, equal to replayIndex if there are none
    private var bufferSize = 0 // number of buffered values
    private var queueSize = 0 // number of queued emitters
    private val slots: MutableList<SharedFlowSlot> = mutableListOf()
    private var subscribers: MutableStateFlow<Int>? = null

    // Computed state
    private val head: Long get() = minOf(minCollectorIndex, replayIndex)
    private val replaySize: Int get() = (head + bufferSize - replayIndex).toInt()
    private val totalSize: Int get() = bufferSize + queueSize
    private val bufferEndIndex: Long get() = head + bufferSize
    private val queueEndIndex: Long get() = head + bufferSize + queueSize
    private val nCollectors: Int get() = slots.size

    private fun Array<Any?>.getBufferAt(index: Long) = get(index.toInt() and (size - 1))
    private fun Array<Any?>.setBufferAt(index: Long, item: Any?) = set(index.toInt() and (size - 1), item)

    override val subscriptionCount: StateFlow<Int>
        get() = synchronized(lock) { subscriptionCounter() }

    private fun subscriptionCounter(): MutableStateFlow<Int> {
        val existing = subscribers
        if (existing != null) return existing
        val counter = MutableStateFlow(0)
        subscribers = counter
        return counter
    }

    override val replayCache: List<T>
        get() {
            return synchronized(lock) {
                val replaySize = this.replaySize
                if (replaySize == 0) return@synchronized emptyList()
                val result = ArrayList<T>(replaySize)
                val buffer = buffer!!
                for (i in 0 until replaySize) {
                    @Suppress("UNCHECKED_CAST")
                    result.add(buffer.getBufferAt(replayIndex + i) as T)
                }
                result
            }
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
        val slot = allocateSlot()
        var subscribed = false
        try {
            if (sharing != null) {
                sharing.subscribe()
                subscribed = true
            }
            val collectorContext = currentCoroutineContext()
            while (true) {
                var newValue: Any?
                while (true) {
                    newValue = tryTakeValue(slot) // attempt no-suspend fast path first
                    if (newValue !== NoValue) break
                    awaitValue(slot) // await signal that the new value is available
                }
                collectorContext.ensureActive()
                @Suppress("UNCHECKED_CAST")
                collector(newValue as T)
            }
        } finally {
            freeSlot(slot)
            if (subscribed) sharing?.unsubscribe()
        }
    }

    private fun allocateSlot(): SharedFlowSlot {
        val slot = SharedFlowSlot()
        val counter = synchronized(lock) {
            slot.index = updateNewCollectorIndexLocked()
            slots.add(slot)
            subscriptionCounter()
        }
        counter.update { it + 1 }
        return slot
    }

    private fun freeSlot(slot: SharedFlowSlot) {
        var resumes = EMPTY_RESUMES
        val counter = synchronized(lock) {
            val oldIndex = slot.index
            slot.index = -1L
            slot.cont = null
            slots.remove(slot)
            val counter = subscriptionCounter()
            resumes = updateCollectorIndexLocked(oldIndex)
            counter
        }
        counter.update { it - 1 }
        for (cont in resumes) cont?.resume(Unit)
    }

    private fun updateNewCollectorIndexLocked(): Long {
        val index = replayIndex
        if (index < minCollectorIndex) minCollectorIndex = index
        return index
    }

    // Is called when a collector disappears or changes index, returns a list of continuations to resume
    private fun updateCollectorIndexLocked(oldIndex: Long): Array<CancellableContinuation<Unit>?> {
        if (oldIndex > minCollectorIndex) return EMPTY_RESUMES // nothing changes, it was not min
        // start computing new minimal index of active collectors
        val head = head
        var newMinCollectorIndex = head + bufferSize
        // take into account a special case of sync shared flow that can go past 1st queued emitter
        if (bufferCapacity == 0 && queueSize > 0) newMinCollectorIndex++
        for (slot in slots) {
            if (slot.index >= 0 && slot.index < newMinCollectorIndex) newMinCollectorIndex = slot.index
        }
        if (newMinCollectorIndex <= minCollectorIndex) return EMPTY_RESUMES // nothing changes
        // Compute new buffer size if we drop items we no longer need and no emitter is resumed:
        // We must keep all the items from newMinIndex to the end of buffer
        var newBufferEndIndex = bufferEndIndex // var to grow when waiters are resumed
        val maxResumeCount = if (nCollectors > 0) {
            // If we have collectors we can resume up to maxResumeCount waiting emitters
            // a) queueSize -> that's how many waiting emitters we have
            // b) bufferCapacity - newBufferSize0 -> that's how many we can afford to resume to add w/o exceeding bufferCapacity
            val newBufferSize0 = (newBufferEndIndex - newMinCollectorIndex).toInt()
            minOf(queueSize, bufferCapacity - newBufferSize0)
        } else {
            // If we don't have collectors anymore we must resume all waiting emitters
            queueSize // that's how many waiting emitters we have (at most)
        }
        var resumes = EMPTY_RESUMES
        val newQueueEndIndex = newBufferEndIndex + queueSize
        if (maxResumeCount > 0) { // collect emitters to resume if we have them
            resumes = arrayOfNulls(maxResumeCount)
            var resumeCount = 0
            val buffer = buffer!!
            var curEmitterIndex = newBufferEndIndex
            while (curEmitterIndex < newQueueEndIndex) {
                val emitter = buffer.getBufferAt(curEmitterIndex)
                if (emitter !== NoValue) {
                    emitter as SharedFlowEmitter // must have SharedFlowEmitter class
                    resumes[resumeCount] = emitter.cont
                    resumeCount++
                    buffer.setBufferAt(curEmitterIndex, NoValue) // make as canceled if we moved ahead
                    buffer.setBufferAt(newBufferEndIndex, emitter.value)
                    newBufferEndIndex++
                    if (resumeCount >= maxResumeCount) break // enough resumed, done
                }
                curEmitterIndex++
            }
        }
        // Compute new buffer size -> how many values we now actually have after resume
        val newBufferSize1 = (newBufferEndIndex - head).toInt()
        // Note: When nCollectors == 0 we resume ALL queued emitters and we might have resumed more than bufferCapacity,
        // and newMinCollectorIndex might pointing the wrong place because of that. The easiest way to fix it is by
        // forcing newMinCollectorIndex = newBufferEndIndex. We do not needed to update newBufferSize1 (which could be
        // too big), because the only use of newBufferSize1 in the below code is in the minOf(replay, newBufferSize1)
        // expression, which coerces values that are too big anyway.
        if (nCollectors == 0) newMinCollectorIndex = newBufferEndIndex
        // Compute new replay size -> limit to replay the number of items we need, take into account that it can only grow
        var newReplayIndex = maxOf(replayIndex, newBufferEndIndex - minOf(replay, newBufferSize1))
        // adjustment for synchronous case with cancelled emitter (NoValue)
        if (bufferCapacity == 0 && newReplayIndex < newQueueEndIndex && buffer!!.getBufferAt(newReplayIndex) === NoValue) {
            newBufferEndIndex++
            newReplayIndex++
        }
        // Update buffer state
        updateBufferLocked(newReplayIndex, newMinCollectorIndex, newBufferEndIndex, newQueueEndIndex)
        // just in case we've moved all buffered emitters and have NoValue's at the tail now
        cleanupTailLocked()
        // We need to waken up suspended collectors if any emitters were resumed here
        if (resumes.size > 0) resumes = findSlotsToResumeLocked(resumes)
        return resumes
    }

    private fun updateBufferLocked(
        newReplayIndex: Long,
        newMinCollectorIndex: Long,
        newBufferEndIndex: Long,
        newQueueEndIndex: Long
    ) {
        // Compute new head value
        val newHead = minOf(newMinCollectorIndex, newReplayIndex)
        // cleanup items we don't have to buffer anymore (because head is about to move)
        val buffer = buffer
        if (buffer != null) {
            var index = head
            while (index < newHead) {
                buffer.setBufferAt(index, null)
                index++
            }
        }
        // update all state variables to newly computed values
        replayIndex = newReplayIndex
        minCollectorIndex = newMinCollectorIndex
        bufferSize = (newBufferEndIndex - newHead).toInt()
        queueSize = (newQueueEndIndex - newBufferEndIndex).toInt()
    }

    // Removes all the NoValue items from the end of the queue and reduces its size
    private fun cleanupTailLocked() {
        // If we have synchronous case, then keep one emitter queued
        if (bufferCapacity == 0 && queueSize <= 1) return
        val buffer = buffer ?: return
        while (queueSize > 0 && buffer.getBufferAt(head + totalSize - 1) === NoValue) {
            queueSize--
            buffer.setBufferAt(head + totalSize, null)
        }
    }

    // returns NoValue if cannot take value without suspension
    private fun tryTakeValue(slot: SharedFlowSlot): Any? {
        var resumes = EMPTY_RESUMES
        val value = synchronized(lock) {
            val index = tryPeekLocked(slot)
            if (index < 0) {
                NoValue
            } else {
                val oldIndex = slot.index
                val newValue = getPeekedValueLockedAt(index)
                slot.index = index + 1 // points to the next index after peeked one
                resumes = updateCollectorIndexLocked(oldIndex)
                newValue
            }
        }
        for (resume in resumes) resume?.resume(Unit)
        return value
    }

    // returns -1 if cannot peek value without suspension
    private fun tryPeekLocked(slot: SharedFlowSlot): Long {
        // return buffered value if possible
        val index = slot.index
        if (index < bufferEndIndex) return index
        if (bufferCapacity > 0) return -1L // if there's a buffer, never try to rendezvous with emitters
        // Synchronous shared flow (bufferCapacity == 0) tries to rendezvous
        if (index > head) return -1L // ... but only with the first emitter (never look forward)
        if (queueSize == 0) return -1L // nothing there to rendezvous with
        return index // rendezvous with the first emitter
    }

    private fun getPeekedValueLockedAt(index: Long): Any? =
        when (val item = buffer!!.getBufferAt(index)) {
            is SharedFlowEmitter -> item.value
            else -> item
        }

    private suspend fun awaitValue(slot: SharedFlowSlot) = suspendCancellableCoroutine<Unit> { cont ->
        // recheck under the emitter/collector update boundary
        val shouldResume = synchronized(lock) {
            if (tryPeekLocked(slot) < 0) {
                slot.cont = cont // Ok -- suspending
                false
            } else {
                true
            }
        }
        if (shouldResume) cont.resume(Unit) // has value, no need to suspend
    }

    private fun findSlotsToResumeLocked(
        resumesIn: Array<CancellableContinuation<Unit>?>
    ): Array<CancellableContinuation<Unit>?> {
        var resumes = resumesIn
        var resumeCount = resumesIn.size
        for (slot in slots) {
            val cont = slot.cont ?: continue // only waiting slots
            if (tryPeekLocked(slot) < 0) continue // only slots that can peek a value
            if (resumeCount >= resumes.size) resumes = resumes.copyOf(maxOf(2, 2 * resumes.size))
            resumes[resumeCount] = cont
            resumeCount++
            slot.cont = null // not waiting anymore
        }
        return resumes
    }

    private fun dropOldestLocked() {
        buffer?.setBufferAt(head, null)
        bufferSize--
        val newHead = head + 1
        if (replayIndex < newHead) replayIndex = newHead
        if (minCollectorIndex < newHead) correctCollectorIndexesOnDropOldest(newHead)
    }

    private fun correctCollectorIndexesOnDropOldest(newHead: Long) {
        for (slot in slots) {
            if (slot.index >= 0 && slot.index < newHead) {
                slot.index = newHead // force move it up (this collector was too slow and missed the value at its index)
            }
        }
        minCollectorIndex = newHead
    }

    // enqueues item to buffer array, caller shall increment either bufferSize or queueSize
    private fun enqueueLocked(item: Any?) {
        val curSize = totalSize
        val buffer = when (val curBuffer = buffer) {
            null -> growBuffer(null, 0, 2)
            else -> if (curSize >= curBuffer.size) growBuffer(curBuffer, curSize, curBuffer.size * 2) else curBuffer
        }
        buffer.setBufferAt(head + curSize, item)
    }

    private fun growBuffer(curBuffer: Array<Any?>?, curSize: Int, newSize: Int): Array<Any?> {
        check(newSize > 0) { "Buffer size overflow" }
        val newBuffer = arrayOfNulls<Any?>(newSize)
        buffer = newBuffer
        if (curBuffer == null) return newBuffer
        val head = head
        var i = 0
        while (i < curSize) {
            newBuffer.setBufferAt(head + i, curBuffer.getBufferAt(head + i))
            i++
        }
        return newBuffer
    }

    private fun tryEmitNoCollectorsLocked(value: T): Boolean {
        if (replay == 0) return true // no need to replay, just forget it now
        enqueueLocked(value) // enqueue to replayCache
        bufferSize++ // value was added to buffer
        // drop oldest from the buffer if it became more than replay
        if (bufferSize > replay) dropOldestLocked()
        minCollectorIndex = head + bufferSize // a default value (max allowed)
        return true
    }

    private fun tryEmitLocked(value: T): Boolean {
        // Fast path without collectors -> no buffering beyond replay
        if (nCollectors == 0) return tryEmitNoCollectorsLocked(value) // always returns true
        // With collectors we'll have to buffer
        // cannot emit now if buffer is full & blocked by slow collectors
        if (bufferSize >= bufferCapacity && minCollectorIndex <= replayIndex) {
            when (onBufferOverflow) {
                BufferOverflow.SUSPEND -> return false // will suspend
                BufferOverflow.DROP_LATEST -> return true // just drop incoming
                BufferOverflow.DROP_OLDEST -> {} // force enqueue & drop oldest instead
            }
        }
        enqueueLocked(value)
        bufferSize++ // value was added to buffer
        // drop oldest from the buffer if it became more than bufferCapacity
        if (bufferSize > bufferCapacity) dropOldestLocked()
        // keep replaySize not larger that needed
        if (replaySize > replay) { // increment replayIndex by one
            updateBufferLocked(replayIndex + 1, minCollectorIndex, bufferEndIndex, queueEndIndex)
        }
        return true
    }

    override fun tryEmit(value: T): Boolean {
        var resumes = EMPTY_RESUMES
        val emitted = synchronized(lock) {
            if (tryEmitLocked(value)) {
                resumes = findSlotsToResumeLocked(resumes)
                true
            } else {
                false
            }
        }
        for (cont in resumes) cont?.resume(Unit)
        return emitted
    }

    override suspend fun emit(value: T) {
        if (tryEmit(value)) return // fast-path
        emitSuspend(value)
    }

    private suspend fun emitSuspend(value: T) = suspendCancellableCoroutine<Unit> { cont ->
        var resumes = EMPTY_RESUMES
        var emitter: SharedFlowEmitter? = null
        var shouldResume = false
        synchronized(lock) {
            // recheck buffer state again (a collector may have moved in between)
            if (tryEmitLocked(value)) {
                shouldResume = true
                resumes = findSlotsToResumeLocked(resumes)
            } else {
                // add suspended emitter to the buffer
                val queuedEmitter = SharedFlowEmitter(head + totalSize, value, cont)
                enqueueLocked(queuedEmitter)
                queueSize++ // added to queue of waiting emitters
                emitter = queuedEmitter
                // synchronous shared flow might rendezvous with waiting emitter
                if (bufferCapacity == 0) resumes = findSlotsToResumeLocked(resumes)
            }
        }
        if (shouldResume) cont.resume(Unit)
        // outside of the state update: register cancellation, then resume slots
        emitter?.let { em -> cont.invokeOnCancellation { cancelEmitter(em) } }
        for (r in resumes) r?.resume(Unit)
    }

    private fun cancelEmitter(emitter: SharedFlowEmitter) {
        synchronized(lock) {
            if (emitter.index < head) return@synchronized // already skipped past this index
            val buffer = buffer ?: return@synchronized
            if (buffer.getBufferAt(emitter.index) !== emitter) return@synchronized // already resumed
            buffer.setBufferAt(emitter.index, NoValue)
            cleanupTailLocked()
        }
    }

    override fun resetReplayCache() {
        // Update buffer state
        synchronized(lock) {
            updateBufferLocked(
                newReplayIndex = bufferEndIndex,
                newMinCollectorIndex = minCollectorIndex,
                newBufferEndIndex = bufferEndIndex,
                newQueueEndIndex = queueEndIndex
            )
        }
    }
}

private val EMPTY_RESUMES = arrayOfNulls<CancellableContinuation<Unit>>(0)

public suspend fun <T> Flow<T>.shareIn(replay: Int): SharedFlow<T> {
    val shared = MutableSharedFlow<T>(replay)
    val source = this
    source.collect { value ->
        @Suppress("UNCHECKED_CAST")
        shared.tryEmit(value as T)
    }
    return shared
}
