@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject

// KUU-4032: java.util.concurrent.LinkedBlockingQueue — a bounded FIFO over a
// lock-guarded kotlin.collections.ArrayDeque. Producers park on `notFull`
// handles while the queue is at capacity and consumers park on `notEmpty`
// handles while it is empty; every state change wakes the opposing side,
// which re-checks its condition under the guard, so spurious wakeups are
// harmless. Iterators and toArray are snapshots taken under the guard —
// weakly consistent like the JVM ones, never ConcurrentModificationException.
public class LinkedBlockingQueue<E> : BlockingQueue<E> {
    private val guard = SynchronizedObject()
    private val storage: ArrayDeque<E>
    private val capacity: Int
    private val notEmptyWaiters = ArrayList<ParkingHandle>()
    private val notFullWaiters = ArrayList<ParkingHandle>()

    public constructor() : this(Int.MAX_VALUE)

    public constructor(capacity: Int) {
        if (capacity <= 0) throw IllegalArgumentException("capacity <= 0")
        this.capacity = capacity
        this.storage = ArrayDeque<E>()
    }

    public constructor(elements: Collection<E>) : this(Int.MAX_VALUE) {
        guard.lock()
        try {
            for (element in elements) {
                if (element == null) throw NullPointerException()
                storage.addLast(element)
            }
        } finally {
            guard.unlock()
        }
    }

    override val size: Int
        get() {
            guard.lock()
            try {
                return storage.size
            } finally {
                guard.unlock()
            }
        }

    override fun isEmpty(): Boolean {
        guard.lock()
        try {
            return storage.isEmpty()
        } finally {
            guard.unlock()
        }
    }

    override fun remainingCapacity(): Int {
        guard.lock()
        try {
            return capacity - storage.size
        } finally {
            guard.unlock()
        }
    }

    override fun add(element: E): Boolean {
        if (offer(element)) return true
        throw IllegalStateException("Queue full")
    }

    override fun offer(element: E): Boolean {
        if (element == null) throw NullPointerException()
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (storage.size >= capacity) return false
            storage.addLast(element)
            release = drainWaiters(notEmptyWaiters)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return true
    }

    override fun offer(element: E, timeout: Long, unit: TimeUnit): Boolean {
        if (element == null) throw NullPointerException()
        return offerNanos(element, unit.toNanos(timeout), blocking = false)
    }

    override fun put(element: E) {
        if (element == null) throw NullPointerException()
        offerNanos(element, -1L, blocking = true)
    }

    override fun addAll(elements: Collection<E>): Boolean {
        // JVM addAll applies add() element by element, so it can leave a
        // partial batch behind when the queue fills up mid-way.
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    override fun poll(): E? {
        var head: E? = null
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (storage.isEmpty()) return null
            head = storage.removeFirst()
            release = drainWaiters(notFullWaiters)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return head
    }

    override fun poll(timeout: Long, unit: TimeUnit): E? =
        pollNanos(unit.toNanos(timeout), blocking = false)

    override fun take(): E {
        val head = pollNanos(-1L, blocking = true)
        return head ?: throw IllegalStateException("unreachable: untimed take cannot time out")
    }

    /** JVM `Queue.remove`: like [poll] but throws on an empty queue. */
    public fun remove(): E {
        val head = poll()
        return head ?: throw NoSuchElementException()
    }

    override fun element(): E {
        guard.lock()
        try {
            if (storage.isEmpty()) throw NoSuchElementException()
            return storage.first()
        } finally {
            guard.unlock()
        }
    }

    override fun peek(): E? {
        guard.lock()
        try {
            return storage.firstOrNull()
        } finally {
            guard.unlock()
        }
    }

    override fun contains(element: E): Boolean {
        guard.lock()
        try {
            return storage.contains(element)
        } finally {
            guard.unlock()
        }
    }

    override fun containsAll(elements: Collection<E>): Boolean {
        guard.lock()
        try {
            return storage.containsAll(elements)
        } finally {
            guard.unlock()
        }
    }

    override fun remove(element: E): Boolean {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (!storage.remove(element)) return false
            release = drainWaiters(notFullWaiters)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return true
    }

    override fun removeAll(elements: Collection<E>): Boolean {
        var removed = false
        val release: List<ParkingHandle>
        guard.lock()
        try {
            removed = storage.removeAll(elements)
            release = if (removed) drainWaiters(notFullWaiters) else emptyList()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return removed
    }

    override fun retainAll(elements: Collection<E>): Boolean {
        var removed = false
        val release: List<ParkingHandle>
        guard.lock()
        try {
            removed = storage.retainAll(elements)
            release = if (removed) drainWaiters(notFullWaiters) else emptyList()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return removed
    }

    override fun clear() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (storage.isEmpty()) return
            storage.clear()
            release = drainWaiters(notFullWaiters)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    override fun drainTo(target: MutableCollection<in E>): Int =
        drainTo(target, Int.MAX_VALUE)

    override fun drainTo(target: MutableCollection<in E>, maxElements: Int): Int {
        if (maxElements <= 0) return 0
        var moved = 0
        val release: List<ParkingHandle>
        guard.lock()
        try {
            while (moved < maxElements && !storage.isEmpty()) {
                target.add(storage.removeFirst())
                moved += 1
            }
            release = if (moved > 0) drainWaiters(notFullWaiters) else emptyList()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return moved
    }

    override fun iterator(): MutableIterator<E> {
        guard.lock()
        try {
            return storage.toList().toMutableList().iterator()
        } finally {
            guard.unlock()
        }
    }

    public fun toArray(): Array<Any?> {
        guard.lock()
        try {
            return storage.toArray()
        } finally {
            guard.unlock()
        }
    }

    override fun toString(): String {
        guard.lock()
        try {
            return storage.toString()
        } finally {
            guard.unlock()
        }
    }

    // ---- blocking internals ----

    /** Removes every registered handle and returns it for a post-unlock unpark. */
    private fun drainWaiters(waiters: ArrayList<ParkingHandle>): List<ParkingHandle> {
        if (waiters.isEmpty()) return emptyList()
        val drained = ArrayList(waiters)
        waiters.clear()
        return drained
    }

    private fun offerNanos(element: E, nanos: Long, blocking: Boolean): Boolean {
        val handle = ParkingSupport.currentThreadHandle()
        val deadline = jucDeadlineNanos(nanos)
        var registered = false
        while (true) {
            var enqueued = false
            var release: List<ParkingHandle> = emptyList()
            var expired = false
            guard.lock()
            try {
                if (storage.size < capacity) {
                    storage.addLast(element)
                    enqueued = true
                    if (registered) {
                        notFullWaiters.remove(handle)
                        registered = false
                    }
                    release = drainWaiters(notEmptyWaiters)
                } else if (!blocking && nanos <= 0L) {
                    expired = true
                } else {
                    if (!registered) {
                        notFullWaiters.add(handle)
                        registered = true
                    }
                }
            } finally {
                guard.unlock()
            }
            jucUnparkAll(release)
            if (enqueued) return true
            if (expired) return false
            val left = jucNanosLeft(deadline)
            if (left <= 0L) {
                guard.lock()
                try {
                    if (registered) {
                        notFullWaiters.remove(handle)
                        registered = false
                    }
                    // A removal racing the timeout may have freed a slot;
                    // honour it rather than reporting a false timeout.
                    if (storage.size < capacity) {
                        storage.addLast(element)
                        enqueued = true
                    }
                } finally {
                    guard.unlock()
                }
                return enqueued
            }
            jucPark(if (deadline < 0L) -1L else left)
        }
    }

    private fun pollNanos(nanos: Long, blocking: Boolean): E? {
        val handle = ParkingSupport.currentThreadHandle()
        val deadline = jucDeadlineNanos(nanos)
        var registered = false
        while (true) {
            var head: E? = null
            var taken = false
            var release: List<ParkingHandle> = emptyList()
            var expired = false
            guard.lock()
            try {
                if (!storage.isEmpty()) {
                    head = storage.removeFirst()
                    taken = true
                    if (registered) {
                        notEmptyWaiters.remove(handle)
                        registered = false
                    }
                    release = drainWaiters(notFullWaiters)
                } else if (!blocking && nanos <= 0L) {
                    expired = true
                } else {
                    if (!registered) {
                        notEmptyWaiters.add(handle)
                        registered = true
                    }
                }
            } finally {
                guard.unlock()
            }
            jucUnparkAll(release)
            if (taken) return head
            if (expired) return null
            val left = jucNanosLeft(deadline)
            if (left <= 0L) {
                guard.lock()
                try {
                    if (registered) {
                        notEmptyWaiters.remove(handle)
                        registered = false
                    }
                    // An insert racing the timeout may have delivered an
                    // element; honour it rather than reporting a false
                    // timeout.
                    if (!storage.isEmpty()) {
                        head = storage.removeFirst()
                        taken = true
                    }
                } finally {
                    guard.unlock()
                }
                return if (taken) head else null
            }
            jucPark(if (deadline < 0L) -1L else left)
        }
    }
}
