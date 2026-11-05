@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject

// KUU-3994: java.util.concurrent.SynchronousQueue — a zero-capacity handoff
// queue. Nothing is ever stored: each put/offer pairs directly with a waiting
// take/poll, so offer() succeeds only while a consumer is already blocked and
// poll() returns an element only while a producer is waiting. size() is
// therefore always 0 and remainingCapacity() always 0, matching the JDK.
//
// Implementation: a single atomicfu guard serializes the two FIFO waiter lists
// (producers waiting to hand off, consumers waiting to receive). The lists are
// mutually exclusive — a producer only registers when no consumer waits and
// vice versa — so at most one side is ever non-empty. Matching removes the
// head waiter, writes its result slot, and unparks it after the guard is
// released; waiters re-check their slot under the guard after every wake, so
// spurious wakeups and park/unpark races are harmless (the same scheme
// LinkedBlockingQueue uses). Timed waits re-check state under the guard before
// reporting a timeout, so a handoff that committed concurrently is honoured
// rather than reported as expired.
//
// JVM parity notes:
//  - The JDK `fair` constructor flag selects FIFO vs barging handoff order.
//    The waiter lists here are always FIFO, so the flag is accepted for
//    signature parity but intentionally unobserved (same precedent as
//    ArrayBlockingQueue).
//  - Modern JDKs no longer have SynchronousQueue implement TransferQueue
//    (verified absent on JDK 21, the diff oracle's java.base), so only the
//    BlockingQueue surface is provided here.
//  - put/take cannot be interrupted: the runtime parker has no interrupt
//    channel and bundled java.lang.Thread exposes no interrupt(), matching
//    the other bundled blocking primitives.
public class SynchronousQueue<E>(fair: Boolean = false) : BlockingQueue<E> {
    private val guard = SynchronizedObject()
    private val putWaiters = ArrayList<PutWaiter<E>>()
    private val takeWaiters = ArrayList<TakeWaiter<E>>()

    private class PutWaiter<E>(val handle: ParkingHandle, val value: E) {
        // Set under the guard by the consumer that took this element; the
        // producer then knows its offer/put succeeded.
        var done = false
    }

    private class TakeWaiter<E>(val handle: ParkingHandle) {
        // `received` is written before `done` under the guard; a done waiter
        // always carries a non-null element because null offers are rejected.
        // (Named `received`, not `element`, to stay clear of Queue.element().)
        var done = false
        var received: E? = null
    }

    // ---- Queue / Collection surface: the queue is always logically empty ----

    override fun offer(element: E): Boolean {
        if (element == null) throw NullPointerException()
        var handedOff = false
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (takeWaiters.isNotEmpty()) {
                val consumer = takeWaiters.removeAt(0)
                consumer.received = element
                consumer.done = true
                handedOff = true
                release = listOf(consumer.handle)
            } else {
                release = emptyList()
            }
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
        return handedOff
    }

    override fun poll(): E? = pollNanos(0L, blocking = false)

    override fun peek(): E? = null

    override fun element(): E = throw NoSuchElementException()

    /** JVM `Queue.remove`: like [poll] but throws on an empty queue. */
    override fun remove(): E {
        val head = poll()
        return head ?: throw NoSuchElementException()
    }

    override fun add(element: E): Boolean {
        if (offer(element)) return true
        throw IllegalStateException("Queue full")
    }

    override fun put(element: E) {
        if (element == null) throw NullPointerException()
        offerNanos(element, -1L, blocking = true)
    }

    override fun take(): E {
        val head = pollNanos(-1L, blocking = true)
        return head ?: throw IllegalStateException("unreachable: untimed take cannot time out")
    }

    override fun offer(element: E, timeout: Long, unit: TimeUnit): Boolean {
        if (element == null) throw NullPointerException()
        return offerNanos(element, unit.toNanos(timeout), blocking = false)
    }

    override fun poll(timeout: Long, unit: TimeUnit): E? =
        pollNanos(unit.toNanos(timeout), blocking = false)

    override fun remainingCapacity(): Int = 0

    override fun drainTo(target: MutableCollection<in E>): Int = 0

    override fun drainTo(target: MutableCollection<in E>, maxElements: Int): Int = 0

    override val size: Int
        get() = 0

    override fun isEmpty(): Boolean = true

    override fun contains(element: E): Boolean = false

    override fun containsAll(elements: Collection<E>): Boolean = elements.isEmpty()

    override fun remove(element: E): Boolean = false

    override fun removeAll(elements: Collection<E>): Boolean = false

    override fun retainAll(elements: Collection<E>): Boolean = false

    override fun clear() {}

    override fun addAll(elements: Collection<E>): Boolean {
        // JVM AbstractCollection.addAll applies add() element by element, so
        // the first element throws IllegalStateException when no consumer is
        // waiting — an empty collection simply returns false.
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    override fun iterator(): MutableIterator<E> = mutableListOf<E>().iterator()

    public fun toArray(): Array<Any?> = emptyArray()

    override fun toString(): String = "[]"

    // ---- blocking internals ----

    /**
     * Producer side of the rendezvous. Returns true once [element] has been
     * handed to a consumer — either immediately or after parking. With
     * `blocking = false` a non-positive [nanos] degrades to a single attempt.
     */
    private fun offerNanos(element: E, nanos: Long, blocking: Boolean): Boolean {
        val handle = ParkingSupport.currentThreadHandle()
        val waiter = PutWaiter(handle, element)
        val deadline = jucDeadlineNanos(nanos)
        var registered = false
        while (true) {
            var handedOff = false
            var giveUp = false
            val release: List<ParkingHandle>
            guard.lock()
            try {
                if (registered) {
                    if (waiter.done) {
                        // A consumer already took the element and removed us
                        // from putWaiters under this same guard.
                        handedOff = true
                        release = emptyList()
                    } else if (!blocking && nanos <= 0L) {
                        putWaiters.remove(waiter)
                        registered = false
                        giveUp = true
                        release = emptyList()
                    } else {
                        release = emptyList()
                    }
                } else if (takeWaiters.isNotEmpty()) {
                    val consumer = takeWaiters.removeAt(0)
                    consumer.received = element
                    consumer.done = true
                    handedOff = true
                    release = listOf(consumer.handle)
                } else if (!blocking && nanos <= 0L) {
                    giveUp = true
                    release = emptyList()
                } else {
                    putWaiters.add(waiter)
                    registered = true
                    release = emptyList()
                }
            } finally {
                guard.unlock()
            }
            jucUnparkAll(release)
            if (handedOff) return true
            if (giveUp) return false
            val left = jucNanosLeft(deadline)
            if (left <= 0L) {
                // Deadline expired. Every iteration that reaches this point
                // has already registered the waiter (the unregistered branches
                // all return), so only the done/deregister decision remains.
                // A consumer that matched us first sets `done` under the same
                // guard, which wins over the timeout.
                var lastChance = false
                guard.lock()
                try {
                    if (waiter.done) {
                        lastChance = true
                    } else {
                        putWaiters.remove(waiter)
                    }
                } finally {
                    guard.unlock()
                }
                return lastChance
            }
            jucPark(if (deadline < 0L) -1L else left)
        }
    }

    /**
     * Consumer side of the rendezvous. Returns the handed-off element, or
     * null/timeout per [blocking] and [nanos].
     */
    private fun pollNanos(nanos: Long, blocking: Boolean): E? {
        val handle = ParkingSupport.currentThreadHandle()
        val waiter = TakeWaiter<E>(handle)
        val deadline = jucDeadlineNanos(nanos)
        var registered = false
        while (true) {
            var element: E? = null
            var taken = false
            var giveUp = false
            var release: List<ParkingHandle> = emptyList()
            guard.lock()
            try {
                if (registered) {
                    if (waiter.done) {
                        // A producer already delivered and removed us from
                        // takeWaiters under this same guard.
                        element = waiter.received
                        taken = true
                    } else if (!blocking && nanos <= 0L) {
                        takeWaiters.remove(waiter)
                        registered = false
                        giveUp = true
                    }
                } else if (putWaiters.isNotEmpty()) {
                    val producer = putWaiters.removeAt(0)
                    producer.done = true
                    element = producer.value
                    taken = true
                    release = listOf(producer.handle)
                } else if (!blocking && nanos <= 0L) {
                    giveUp = true
                } else {
                    takeWaiters.add(waiter)
                    registered = true
                }
            } finally {
                guard.unlock()
            }
            jucUnparkAll(release)
            if (taken) return element
            if (giveUp) return null
            val left = jucNanosLeft(deadline)
            if (left <= 0L) {
                // Same expiry path as offerNanos: the waiter is always
                // registered here, and a producer that matched us first wins
                // over the timeout via `done`.
                var lastElement: E? = null
                var lastTaken = false
                guard.lock()
                try {
                    if (waiter.done) {
                        lastElement = waiter.received
                        lastTaken = true
                    } else {
                        takeWaiters.remove(waiter)
                    }
                } finally {
                    guard.unlock()
                }
                return if (lastTaken) lastElement else null
            }
            jucPark(if (deadline < 0L) -1L else left)
        }
    }
}
