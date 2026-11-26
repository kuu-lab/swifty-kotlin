@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlin.concurrent.Volatile

public class CountDownLatch(count: Int) {
    private val guard = SynchronizedObject()
    private val waiters = ArrayList<ParkingHandle>()

    @Volatile
    private var remaining: Int

    init {
        if (count < 0) throw IllegalArgumentException("count < 0")
        remaining = count
    }

    public val count: Long
        get() = remaining.toLong()

    public fun countDown() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (remaining == 0) return
            remaining -= 1
            if (remaining != 0) return
            release = ArrayList(waiters)
            waiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    public fun await() {
        awaitNanos(-1L)
    }

    public fun await(timeout: Long, unit: TimeUnit): Boolean =
        awaitNanos(unit.toNanos(timeout))

    private fun awaitNanos(nanos: Long): Boolean {
        if (remaining == 0) return true
        val handle = ParkingSupport.currentThreadHandle()
        guard.lock()
        try {
            if (remaining == 0) return true
            waiters.add(handle)
        } finally {
            guard.unlock()
        }
        val deadline = jucDeadlineNanos(nanos)
        try {
            while (true) {
                if (remaining == 0) return true
                val left = jucNanosLeft(deadline)
                if (left <= 0L) return false
                jucPark(if (deadline < 0L) -1L else left)
            }
        } finally {
            guard.lock()
            try {
                waiters.remove(handle)
            } finally {
                guard.unlock()
            }
        }
    }

    override fun toString(): String =
        "CountDownLatch[count = $remaining]"
}
