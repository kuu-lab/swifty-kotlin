@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import java.lang.Runnable
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlin.concurrent.Volatile

// KUU-3059: java.util.concurrent.CyclicBarrier. Each generation parks its
// waiters on their per-thread atomicfu handles; the last arriver runs the
// barrier action and then unparks everyone. Timeout/reset break the barrier
// and unpark the generation with BrokenBarrierException.

public class CyclicBarrier(
    public val parties: Int,
    private val barrierAction: Runnable?
) {
    private val guard = SynchronizedObject()
    private val waiters = ArrayList<ParkingHandle>()

    @Volatile
    private var generation = 0

    @Volatile
    private var broken = false

    private var remaining: Int = parties

    public constructor(parties: Int) : this(parties, null)

    init {
        if (parties <= 0) throw IllegalArgumentException("parties <= 0")
    }

    public val numberWaiting: Int
        get() {
            guard.lock()
            try {
                return waiters.size
            } finally {
                guard.unlock()
            }
        }

    public val isBroken: Boolean
        get() = broken

    public fun await(): Int = awaitNanos(-1L)

    public fun await(timeout: Long, unit: TimeUnit): Int =
        awaitNanos(unit.toNanos(timeout))

    public fun reset() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            broken = false
            generation += 1
            remaining = parties
            release = ArrayList(waiters)
            waiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    private fun breakBarrier() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            broken = true
            generation += 1
            remaining = parties
            release = ArrayList(waiters)
            waiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    private fun awaitNanos(nanos: Long): Int {
        val deadline = jucDeadlineNanos(nanos)
        val handle = ParkingSupport.currentThreadHandle()
        val release = ArrayList<ParkingHandle>()
        val myGeneration: Int
        val index: Int
        guard.lock()
        if (broken) {
            guard.unlock()
            throw BrokenBarrierException()
        }
        myGeneration = generation
        remaining -= 1
        index = remaining
        if (index == 0) {
            release.addAll(waiters)
            waiters.clear()
            remaining = parties
            generation += 1
            guard.unlock()
            // The barrier action runs on the last-arriving thread before the
            // generation is released, matching JVM ordering.
            try {
                barrierAction?.run()
            } catch (thrown: Throwable) {
                breakBarrier()
                throw thrown
            }
            jucUnparkAll(release)
            return 0
        }
        waiters.add(handle)
        guard.unlock()
        try {
            while (true) {
                if (broken) throw BrokenBarrierException()
                if (generation != myGeneration) return index
                val left = jucNanosLeft(deadline)
                if (left <= 0L) {
                    breakBarrier()
                    throw TimeoutException()
                }
                jucPark(if (deadline < 0L) -1L else left)
            }
        } finally {
            // A waiter that left early (timeout or a broken barrier) must not
            // leak a stale handle into the next generation.
            guard.lock()
            try {
                waiters.remove(handle)
            } finally {
                guard.unlock()
            }
        }
    }
}
