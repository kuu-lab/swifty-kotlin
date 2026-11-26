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

// Upstream guards every state mutation with `synchronized(this)` and resumes
// continuations outside the lock; the port keeps the same "mutate first,
// resume afterwards" ordering, which matters because resumed coroutines must
// never observe a half-updated buffer.

public interface SharedFlow<out T> : Flow<T> {
    public val replayCache: List<T>

    public suspend fun collect(collector: suspend (T) -> Unit)
}

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
    val bufferCapacity = if (bufferCapacity0 < 0) Int.MAX_VALUE else bufferCapacity0
    return SharedFlowImpl(replay, bufferCapacity, onBufferOverflow)
}

private object NoValue

private class SharedFlowEmitter(
    val index: Long,
    val value: Any?,
    val cont: CancellableContinuation<Unit>
)

private class SharedFlowSlot {
    var index = -1L
    var cont: CancellableContinuation<Unit>? = null
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

    private val lock = SynchronizedObject()
    private var buffer: Array<Any?>? = null
    private var replayIndex = 0L
    private var minCollectorIndex = 0L
    private var bufferSize = 0
    private var queueSize = 0
    private val slots: MutableList<SharedFlowSlot> = mutableListOf()
    private var subscribers: MutableStateFlow<Int>? = null

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
                    newValue = tryTakeValue(slot)
                    if (newValue !== NoValue) break
                    awaitValue(slot)
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

    private fun updateCollectorIndexLocked(oldIndex: Long): Array<CancellableContinuation<Unit>?> {
        if (oldIndex > minCollectorIndex) return EMPTY_RESUMES
        val head = head
        var newMinCollectorIndex = head + bufferSize
        if (bufferCapacity == 0 && queueSize > 0) newMinCollectorIndex++
        for (slot in slots) {
            if (slot.index >= 0 && slot.index < newMinCollectorIndex) newMinCollectorIndex = slot.index
        }
        if (newMinCollectorIndex <= minCollectorIndex) return EMPTY_RESUMES
        var newBufferEndIndex = bufferEndIndex
        val maxResumeCount = if (nCollectors > 0) {
            val newBufferSize0 = (newBufferEndIndex - newMinCollectorIndex).toInt()
            minOf(queueSize, bufferCapacity - newBufferSize0)
        } else {
            queueSize
        }
        var resumes = EMPTY_RESUMES
        val newQueueEndIndex = newBufferEndIndex + queueSize
        if (maxResumeCount > 0) {
            resumes = arrayOfNulls(maxResumeCount)
            var resumeCount = 0
            val buffer = buffer!!
            var curEmitterIndex = newBufferEndIndex
            while (curEmitterIndex < newQueueEndIndex) {
                val emitter = buffer.getBufferAt(curEmitterIndex)
                if (emitter !== NoValue) {
                    emitter as SharedFlowEmitter
                    resumes[resumeCount] = emitter.cont
                    resumeCount++
                    buffer.setBufferAt(curEmitterIndex, NoValue)
                    buffer.setBufferAt(newBufferEndIndex, emitter.value)
                    newBufferEndIndex++
                    if (resumeCount >= maxResumeCount) break
                }
                curEmitterIndex++
            }
        }
        val newBufferSize1 = (newBufferEndIndex - head).toInt()
        // Note: When nCollectors == 0 we resume ALL queued emitters and we might have resumed more than bufferCapacity,
        // and newMinCollectorIndex might pointing the wrong place because of that. The easiest way to fix it is by
        // forcing newMinCollectorIndex = newBufferEndIndex. We do not needed to update newBufferSize1 (which could be
        // too big), because the only use of newBufferSize1 in the below code is in the minOf(replay, newBufferSize1)
        // expression, which coerces values that are too big anyway.
        if (nCollectors == 0) newMinCollectorIndex = newBufferEndIndex
        var newReplayIndex = maxOf(replayIndex, newBufferEndIndex - minOf(replay, newBufferSize1))
        if (bufferCapacity == 0 && newReplayIndex < newQueueEndIndex && buffer!!.getBufferAt(newReplayIndex) === NoValue) {
            newBufferEndIndex++
            newReplayIndex++
        }
        updateBufferLocked(newReplayIndex, newMinCollectorIndex, newBufferEndIndex, newQueueEndIndex)
        cleanupTailLocked()
        if (resumes.size > 0) resumes = findSlotsToResumeLocked(resumes)
        return resumes
    }

    private fun updateBufferLocked(
        newReplayIndex: Long,
        newMinCollectorIndex: Long,
        newBufferEndIndex: Long,
        newQueueEndIndex: Long
    ) {
        val newHead = minOf(newMinCollectorIndex, newReplayIndex)
        val buffer = buffer
        if (buffer != null) {
            var index = head
            while (index < newHead) {
                buffer.setBufferAt(index, null)
                index++
            }
        }
        replayIndex = newReplayIndex
        minCollectorIndex = newMinCollectorIndex
        bufferSize = (newBufferEndIndex - newHead).toInt()
        queueSize = (newQueueEndIndex - newBufferEndIndex).toInt()
    }

    private fun cleanupTailLocked() {
        if (bufferCapacity == 0 && queueSize <= 1) return
        val buffer = buffer ?: return
        while (queueSize > 0 && buffer.getBufferAt(head + totalSize - 1) === NoValue) {
            queueSize--
            buffer.setBufferAt(head + totalSize, null)
        }
    }

    private fun tryTakeValue(slot: SharedFlowSlot): Any? {
        var resumes = EMPTY_RESUMES
        val value = synchronized(lock) {
            val index = tryPeekLocked(slot)
            if (index < 0) {
                NoValue
            } else {
                val oldIndex = slot.index
                val newValue = getPeekedValueLockedAt(index)
                slot.index = index + 1
                resumes = updateCollectorIndexLocked(oldIndex)
                newValue
            }
        }
        for (resume in resumes) resume?.resume(Unit)
        return value
    }

    private fun tryPeekLocked(slot: SharedFlowSlot): Long {
        val index = slot.index
        if (index < bufferEndIndex) return index
        if (bufferCapacity > 0) return -1L
        if (index > head) return -1L
        if (queueSize == 0) return -1L
        return index
    }

    private fun getPeekedValueLockedAt(index: Long): Any? =
        when (val item = buffer!!.getBufferAt(index)) {
            is SharedFlowEmitter -> item.value
            else -> item
        }

    private suspend fun awaitValue(slot: SharedFlowSlot) = suspendCancellableCoroutine<Unit> { cont ->
        val shouldResume = synchronized(lock) {
            if (tryPeekLocked(slot) < 0) {
                slot.cont = cont
                false
            } else {
                true
            }
        }
        if (shouldResume) cont.resume(Unit)
    }

    private fun findSlotsToResumeLocked(
        resumesIn: Array<CancellableContinuation<Unit>?>
    ): Array<CancellableContinuation<Unit>?> {
        var resumes = resumesIn
        var resumeCount = resumesIn.size
        for (slot in slots) {
            val cont = slot.cont ?: continue
            if (tryPeekLocked(slot) < 0) continue
            if (resumeCount >= resumes.size) resumes = resumes.copyOf(maxOf(2, 2 * resumes.size))
            resumes[resumeCount] = cont
            resumeCount++
            slot.cont = null
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
                slot.index = newHead
            }
        }
        minCollectorIndex = newHead
    }

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
        if (replay == 0) return true
        enqueueLocked(value)
        bufferSize++
        if (bufferSize > replay) dropOldestLocked()
        minCollectorIndex = head + bufferSize
        return true
    }

    private fun tryEmitLocked(value: T): Boolean {
        if (nCollectors == 0) return tryEmitNoCollectorsLocked(value)
        if (bufferSize >= bufferCapacity && minCollectorIndex <= replayIndex) {
            when (onBufferOverflow) {
                BufferOverflow.SUSPEND -> return false
                BufferOverflow.DROP_LATEST -> return true
                BufferOverflow.DROP_OLDEST -> {}
            }
        }
        enqueueLocked(value)
        bufferSize++
        if (bufferSize > bufferCapacity) dropOldestLocked()
        if (replaySize > replay) {
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
        if (tryEmit(value)) return
        emitSuspend(value)
    }

    private suspend fun emitSuspend(value: T) = suspendCancellableCoroutine<Unit> { cont ->
        var resumes = EMPTY_RESUMES
        var emitter: SharedFlowEmitter? = null
        var shouldResume = false
        synchronized(lock) {
            if (tryEmitLocked(value)) {
                shouldResume = true
                resumes = findSlotsToResumeLocked(resumes)
            } else {
                val queuedEmitter = SharedFlowEmitter(head + totalSize, value, cont)
                enqueueLocked(queuedEmitter)
                queueSize++
                emitter = queuedEmitter
                if (bufferCapacity == 0) resumes = findSlotsToResumeLocked(resumes)
            }
        }
        if (shouldResume) cont.resume(Unit)
        emitter?.let { em -> cont.invokeOnCancellation { cancelEmitter(em) } }
        for (r in resumes) r?.resume(Unit)
    }

    private fun cancelEmitter(emitter: SharedFlowEmitter) {
        synchronized(lock) {
            if (emitter.index < head) return@synchronized
            val buffer = buffer ?: return@synchronized
            if (buffer.getBufferAt(emitter.index) !== emitter) return@synchronized
            buffer.setBufferAt(emitter.index, NoValue)
            cleanupTailLocked()
        }
    }

    override fun resetReplayCache() {
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
