@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlin.concurrent.Volatile

// KUU-3059: java.util.concurrent.Semaphore. Permits are guarded by an
// atomicfu recursive lock; blocked acquirers park on their per-thread handle
// and re-check after every unpark, which keeps the woken set FIFO and makes
// spurious wakeups harmless. The `fair` flag is accepted for signature parity
// — wakeups are always FIFO here.

public class Semaphore(permits: Int, fair: Boolean = false) {
    private val guard = SynchronizedObject()
    private val waiters = ArrayList<ParkingHandle>()

    @Volatile
    private var available: Int

    public val isFair: Boolean = fair

    init {
        if (permits < 0) throw IllegalArgumentException("permits < 0")
        available = permits
    }

    public fun availablePermits(): Int {
        guard.lock()
        try {
            return available
        } finally {
            guard.unlock()
        }
    }

    public fun drainPermits(): Int {
        guard.lock()
        try {
            val drained = available
            available = 0
            return drained
        } finally {
            guard.unlock()
        }
    }

    public fun acquire() {
        acquirePermits(1)
    }

    public fun acquire(permits: Int) {
        acquirePermits(permits)
    }

    public fun acquireUninterruptibly() {
        acquirePermits(1)
    }

    public fun tryAcquire(): Boolean = tryAcquirePermits(1, -1L)

    public fun tryAcquire(permits: Int): Boolean = tryAcquirePermits(permits, -1L)

    public fun tryAcquire(timeout: Long, unit: TimeUnit): Boolean =
        tryAcquirePermits(1, unit.toNanos(timeout))

    public fun tryAcquire(permits: Int, timeout: Long, unit: TimeUnit): Boolean =
        tryAcquirePermits(permits, unit.toNanos(timeout))

    public fun release() {
        releasePermits(1)
    }

    public fun release(permits: Int) {
        releasePermits(permits)
    }

    public fun hasQueuedThreads(): Boolean {
        guard.lock()
        try {
            return waiters.isNotEmpty()
        } finally {
            guard.unlock()
        }
    }

    public val queueLength: Int
        get() {
            guard.lock()
            try {
                return waiters.size
            } finally {
                guard.unlock()
            }
        }

    private fun acquirePermits(permits: Int) {
        if (!tryAcquirePermits(permits, -1L, blocking = true)) {
            throw IllegalStateException("unreachable: untimed acquire cannot time out")
        }
    }

    private fun releasePermits(permits: Int) {
        if (permits < 0) throw IllegalArgumentException("permits < 0")
        if (permits == 0) return
        val release: List<ParkingHandle>
        guard.lock()
        try {
            available += permits
            release = ArrayList(waiters)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    private fun tryAcquirePermits(permits: Int, nanos: Long, blocking: Boolean = false): Boolean {
        if (permits < 0) throw IllegalArgumentException("permits < 0")
        if (permits == 0) return true
        val handle = ParkingSupport.currentThreadHandle()
        val deadline = jucDeadlineNanos(nanos)
        var registered = false
        while (true) {
            guard.lock()
            try {
                if (available >= permits) {
                    available -= permits
                    if (registered) waiters.remove(handle)
                    return true
                }
                if (!blocking && nanos <= 0L) return false
                if (!registered) {
                    waiters.add(handle)
                    registered = true
                }
            } finally {
                guard.unlock()
            }
            val left = jucNanosLeft(deadline)
            if (left <= 0L) {
                guard.lock()
                try {
                    waiters.remove(handle)
                } finally {
                    guard.unlock()
                }
                // A release racing the timeout may have transferred a permit;
                // honour it rather than reporting a false timeout.
                guard.lock()
                try {
                    if (available >= permits) {
                        available -= permits
                        return true
                    }
                } finally {
                    guard.unlock()
                }
                return false
            }
            jucPark(if (deadline < 0L) -1L else left)
        }
    }
}
