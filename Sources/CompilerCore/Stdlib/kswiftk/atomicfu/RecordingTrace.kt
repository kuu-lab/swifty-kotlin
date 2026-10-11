/*
 * KSwiftK recording extension. The ordinary kotlinx.atomicfu Native API stays no-op.
 * Trace formatting/message conventions derive from atomicfu 0.33.0, fc175fc575419ca9eae0d3c14cefe9c5cd7ca351.
 * Copyright JetBrains s.r.o. Licensed under the Apache License, Version 2.0.
 */
package kswiftk.atomicfu

import kotlinx.atomicfu.TraceBase
import kotlinx.atomicfu.TraceFormat
import kotlinx.atomicfu.traceFormatDefault
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/** A copied entry. Int indices wrap with Kotlin arithmetic; list order remains oldest first. */
public class RecordingTraceEntry(public val index: Int, public val event: Any)

/**
 * Explicit Native recording mode. size is rounded up to a power of two, in 1..1_048_576.
 * Appends and snapshots are linearized by an owned recursive lock. Formatting and
 * event.toString callbacks execute outside that lock. snapshot copies entries;
 * event objects themselves are retained by reference, as in the JVM Trace implementation.
 */
public class RecordingTrace private constructor(
    private val storage: RecordingTraceStorage,
    private val prefix: String?
) : TraceBase() {
    public constructor(size: Int = 32, format: TraceFormat = traceFormatDefault) :
        this(RecordingTraceStorage(size, format), null)

    public val capacity: Int get() = storage.capacity

    /** Named views share storage/indices/format; further names compose outer-to-inner. */
    public fun named(name: String): RecordingTrace =
        RecordingTrace(storage, if (prefix == null) name else "$prefix.$name")

    private fun namedEvent(event: Any): Any =
        if (prefix == null) event else "$prefix.$event"

    override fun append(event: Any) {
        // Named stringification precedes lock acquisition and commits, matching NamedTrace.
        storage.append(namedEvent(event))
    }
    override fun append(event1: Any, event2: Any) {
        val first = namedEvent(event1)
        val second = namedEvent(event2)
        storage.append(first, second)
    }
    override fun append(event1: Any, event2: Any, event3: Any) {
        val first = namedEvent(event1)
        val second = namedEvent(event2)
        val third = namedEvent(event3)
        storage.append(first, second, third)
    }
    override fun append(event1: Any, event2: Any, event3: Any, event4: Any) {
        val first = namedEvent(event1)
        val second = namedEvent(event2)
        val third = namedEvent(event3)
        val fourth = namedEvent(event4)
        storage.append(first, second, third, fourth)
    }

    public fun snapshot(): List<RecordingTraceEntry> = storage.snapshot()

    override fun toString(): String {
        val entries = snapshot()
        val result = StringBuilder()
        var position = 0
        while (position < entries.size) {
            if (position != 0) result.append('\n')
            val entry = entries[position]
            result.append(storage.format.format(entry.index, entry.event))
            position += 1
        }
        return result.toString()
    }
}

private class RecordingTraceStorage(size: Int, val format: TraceFormat) {
    val capacity: Int = recordingTraceCapacity(size)
    private val lock = SynchronizedObject()
    private val events: Array<Any?> = arrayOfNulls(capacity)
    private val indices: IntArray = IntArray(capacity)
    private var head: Int = 0
    private var count: Int = 0
    private var nextIndex: Int = 0

    private fun appendLocked(event: Any) {
        val position: Int
        if (count < capacity) {
            position = (head + count) % capacity
            count += 1
        } else {
            position = head
            head = (head + 1) % capacity
        }
        events[position] = event
        indices[position] = nextIndex
        nextIndex += 1
    }
    fun append(event: Any) { synchronized(lock) { appendLocked(event) } }
    fun append(event1: Any, event2: Any) {
        synchronized(lock) { appendLocked(event1); appendLocked(event2) }
    }
    fun append(event1: Any, event2: Any, event3: Any) {
        synchronized(lock) { appendLocked(event1); appendLocked(event2); appendLocked(event3) }
    }
    fun append(event1: Any, event2: Any, event3: Any, event4: Any) {
        synchronized(lock) { appendLocked(event1); appendLocked(event2); appendLocked(event3); appendLocked(event4) }
    }
    fun snapshot(): List<RecordingTraceEntry> = synchronized(lock) {
        val result = ArrayList<RecordingTraceEntry>(count)
        var position = 0
        while (position < count) {
            val slot = (head + position) % capacity
            result.add(RecordingTraceEntry(indices[slot], events[slot]!!))
            position += 1
        }
        result
    }
}

private fun recordingTraceCapacity(size: Int): Int {
    require(size >= 1 && size <= 1_048_576) { "RecordingTrace size must be in 1..1048576" }
    var capacity = 1
    while (capacity < size) capacity *= 2
    return capacity
}
