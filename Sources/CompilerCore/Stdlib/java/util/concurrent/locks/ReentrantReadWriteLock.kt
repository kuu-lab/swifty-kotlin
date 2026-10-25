@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent.locks

import java.lang.IllegalMonitorStateException
import java.util.concurrent.TimeUnit
import java.util.concurrent.jucDeadlineNanos
import java.util.concurrent.jucNanosLeft
import java.util.concurrent.jucPark
import java.util.concurrent.jucUnparkAll
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlin.concurrent.Volatile

// KUU-3059: java.util.concurrent.locks.ReentrantReadWriteLock. State is
// guarded by an atomicfu recursive lock; waiters park on their per-thread
// handles and re-check after each broadcast. Reentrancy is tracked per
// thread by ParkingHandle identity. Read->write upgrades are not permitted,
// matching the JVM contract (they would deadlock).

public class ReentrantReadWriteLock(private val fairParam: Boolean = false) : ReadWriteLock {
    private val guard = SynchronizedObject()
    private val waiters = ArrayList<ParkingHandle>()
    private val readerHolds = HashMap<ParkingHandle, Int>()

    @Volatile
    private var writer: ParkingHandle? = null
    private var writerHolds = 0

    private val readLockView = ReadLock()
    private val writeLockView = WriteLock()

    public constructor() : this(false)

    // Java isX()/getX() members surface as Kotlin properties under kotlinc —
    // mirror that so the same call sites compile on both compilers.
    public val isFair: Boolean get() = fairParam

    public val isWriteLocked: Boolean
        get() = writer != null

    public val isWriteLockedByCurrentThread: Boolean
        get() = writer === ParkingSupport.currentThreadHandle()

    public val writeHoldCount: Int
        get() = if (isWriteLockedByCurrentThread) writerHolds else 0

    public val readHoldCount: Int
        get() = readerHolds[ParkingSupport.currentThreadHandle()] ?: 0

    public val readLockCount: Int
        get() {
            guard.lock()
            try {
                var total = 0
                for (count in readerHolds.values) total += count
                return total
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

    override fun readLock(): Lock = readLockView

    override fun writeLock(): Lock = writeLockView

    private fun wakeAll() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            release = ArrayList(waiters)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    private fun selfHandle(): ParkingHandle = ParkingSupport.currentThreadHandle()

    public inner class ReadLock : Lock {
        override fun lock() {
            tryLockNanos(-1L)
        }

        override fun lockInterruptibly() {
            lock()
        }

        override fun tryLock(): Boolean = tryLockNanos(0L)

        override fun tryLock(time: Long, unit: TimeUnit): Boolean =
            tryLockNanos(unit.toNanos(time))

        private fun tryLockNanos(nanos: Long): Boolean {
            val handle = selfHandle()
            val deadline = jucDeadlineNanos(nanos)
            var parked = false
            while (true) {
                guard.lock()
                try {
                    val currentWriter = writer
                    if (currentWriter === handle || currentWriter == null ||
                        readerHolds.containsKey(handle)
                    ) {
                        readerHolds[handle] = (readerHolds[handle] ?: 0) + 1
                        if (parked) waiters.remove(handle)
                        return true
                    }
                    if (nanos == 0L) return false
                    if (!parked) {
                        waiters.add(handle)
                        parked = true
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
                    return false
                }
                jucPark(if (deadline < 0L) -1L else left)
            }
        }

        override fun unlock() {
            val handle = selfHandle()
            guard.lock()
            try {
                val holds = readerHolds[handle]
                    ?: throw IllegalMonitorStateException("read unlock by non-owner thread")
                if (holds <= 1) {
                    readerHolds.remove(handle)
                } else {
                    readerHolds[handle] = holds - 1
                }
            } finally {
                guard.unlock()
            }
            wakeAll()
        }

        override fun newCondition(): Condition {
            throw UnsupportedOperationException("ReadLock does not support conditions")
        }
    }

    public inner class WriteLock : Lock {
        override fun lock() {
            tryLockNanos(-1L)
        }

        override fun lockInterruptibly() {
            lock()
        }

        override fun tryLock(): Boolean = tryLockNanos(0L)

        override fun tryLock(time: Long, unit: TimeUnit): Boolean =
            tryLockNanos(unit.toNanos(time))

        private fun tryLockNanos(nanos: Long): Boolean {
            val handle = selfHandle()
            val deadline = jucDeadlineNanos(nanos)
            var parked = false
            while (true) {
                guard.lock()
                try {
                    if (writer === handle) {
                        writerHolds += 1
                        if (parked) waiters.remove(handle)
                        return true
                    }
                    if (writer == null && readerHolds.isEmpty()) {
                        writer = handle
                        writerHolds = 1
                        if (parked) waiters.remove(handle)
                        return true
                    }
                    if (nanos == 0L) return false
                    if (!parked) {
                        waiters.add(handle)
                        parked = true
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
                    return false
                }
                jucPark(if (deadline < 0L) -1L else left)
            }
        }

        override fun unlock() {
            val handle = selfHandle()
            guard.lock()
            try {
                if (writer !== handle) {
                    throw IllegalMonitorStateException("write unlock by non-owner thread")
                }
                writerHolds -= 1
                if (writerHolds == 0) writer = null
            } finally {
                guard.unlock()
            }
            wakeAll()
        }

        override fun newCondition(): Condition = WriteCondition()

        private inner class WriteCondition : Condition {
            private val conditionWaiters = ArrayList<ParkingHandle>()

            private fun requireHeld() {
                if (!isWriteLockedByCurrentThread) {
                    throw IllegalMonitorStateException("condition access by non-owner thread")
                }
            }

            override fun await() {
                awaitNanosInternal(-1L)
            }

            override fun await(time: Long, unit: TimeUnit): Boolean =
                awaitNanosInternal(unit.toNanos(time)) >= 0L

            override fun awaitNanos(nanosTimeout: Long): Long =
                awaitNanosInternal(nanosTimeout)

            private fun awaitNanosInternal(nanos: Long): Long {
                requireHeld()
                val handle = selfHandle()
                guard.lock()
                try {
                    conditionWaiters.add(handle)
                } finally {
                    guard.unlock()
                }
                val savedHolds = writerHolds
                var released = 0
                while (released < savedHolds) {
                    this@WriteLock.unlock()
                    released += 1
                }
                val deadline = jucDeadlineNanos(nanos)
                try {
                    while (true) {
                        guard.lock()
                        val signalled: Boolean
                        try {
                            signalled = !conditionWaiters.contains(handle)
                        } finally {
                            guard.unlock()
                        }
                        if (signalled) break
                        val left = jucNanosLeft(deadline)
                        if (left <= 0L) break
                        jucPark(if (deadline < 0L) -1L else left)
                    }
                } finally {
                    guard.lock()
                    try {
                        conditionWaiters.remove(handle)
                    } finally {
                        guard.unlock()
                    }
                    var reacquired = 0
                    while (reacquired < savedHolds) {
                        this@WriteLock.lock()
                        reacquired += 1
                    }
                }
                return jucNanosLeft(deadline)
            }

            override fun signal() {
                requireHeld()
                val wake: ParkingHandle?
                guard.lock()
                try {
                    wake = if (conditionWaiters.isEmpty()) null else conditionWaiters.removeAt(0)
                } finally {
                    guard.unlock()
                }
                if (wake != null) ParkingSupport.unpark(wake)
            }

            override fun signalAll() {
                requireHeld()
                val wake: List<ParkingHandle>
                guard.lock()
                try {
                    wake = ArrayList(conditionWaiters)
                    conditionWaiters.clear()
                } finally {
                    guard.unlock()
                }
                jucUnparkAll(wake)
            }
        }
    }
}
