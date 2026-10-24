@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent.locks

import java.lang.IllegalMonitorStateException
import java.util.concurrent.TimeUnit
import java.util.concurrent.jucNanosLeft
import java.util.concurrent.jucUnparkAll
import java.util.concurrent.jucPark
import java.util.concurrent.jucDeadlineNanos
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlin.concurrent.Volatile
import kotlin.internal.KsSymbolName

// KUU-3059: java.util.concurrent.locks.ReentrantLock on its own atomicfu
// lock kernel (kind 1 = argument-error on foreign unlock). The kernel is
// recursive per thread; `owner`/`holdCount` are tracked here so Condition
// can release the lock fully and re-acquire it, like the JVM sync fields.

@KsSymbolName("__kk_atomicfu_lock_new")
private external fun newReentrantKernel(ownerErrorKind: Int): Any

@KsSymbolName("__kk_atomicfu_lock_lock")
private external fun lockKernel(kernel: Any): Unit

@KsSymbolName("__kk_atomicfu_lock_try_lock")
private external fun tryLockKernel(kernel: Any, timeoutNanos: Long): Boolean

@KsSymbolName("__kk_atomicfu_lock_unlock")
private external fun unlockKernel(kernel: Any): Unit

public class ReentrantLock(private val fairParam: Boolean = false) : Lock {
    private val kernel: Any = newReentrantKernel(1)
    private val conditionGuard = kotlinx.atomicfu.locks.SynchronizedObject()

    @Volatile
    private var owner: ParkingHandle? = null

    @Volatile
    private var holds = 0

    // Java isX()/getX() members surface as Kotlin properties under kotlinc —
    // mirror that so the same call sites compile on both compilers.
    public val isFair: Boolean get() = fairParam

    override fun lock() {
        lockKernel(kernel)
        recordAcquire()
    }

    override fun lockInterruptibly() {
        lock()
    }

    override fun tryLock(): Boolean {
        if (!tryLockKernel(kernel, 0L)) return false
        recordAcquire()
        return true
    }

    override fun tryLock(time: Long, unit: TimeUnit): Boolean {
        if (!tryLockKernel(kernel, unit.toNanos(time))) return false
        recordAcquire()
        return true
    }

    override fun unlock() {
        if (!isHeldByCurrentThread) throw IllegalMonitorStateException("unlock by non-owner thread")
        holds -= 1
        if (holds == 0) owner = null
        unlockKernel(kernel)
    }

    public val isLocked: Boolean get() = owner != null

    public val isHeldByCurrentThread: Boolean
        get() = owner === ParkingSupport.currentThreadHandle()

    public val holdCount: Int
        get() = if (isHeldByCurrentThread) holds else 0

    private fun recordAcquire() {
        owner = ParkingSupport.currentThreadHandle()
        holds += 1
    }

    override fun newCondition(): Condition = ConditionObject()

    public inner class ConditionObject : Condition {
        private val waiters = ArrayList<ParkingHandle>()

        override fun await() {
            awaitNanosInternal(-1L)
        }

        override fun await(time: Long, unit: TimeUnit): Boolean =
            awaitNanosInternal(unit.toNanos(time)) >= 0L

        override fun awaitNanos(nanosTimeout: Long): Long =
            awaitNanosInternal(nanosTimeout)

        private fun awaitNanosInternal(nanos: Long): Long {
            if (!isHeldByCurrentThread) {
                throw IllegalMonitorStateException("await by non-owner thread")
            }
            val handle = ParkingSupport.currentThreadHandle()
            conditionGuard.lock()
            try {
                waiters.add(handle)
            } finally {
                conditionGuard.unlock()
            }
            val savedHolds = holds
            var released = 0
            while (released < savedHolds) {
                holds -= 1
                if (holds == 0) owner = null
                unlockKernel(kernel)
                released += 1
            }
            val deadline = jucDeadlineNanos(nanos)
            try {
                while (true) {
                    conditionGuard.lock()
                    val signalled: Boolean
                    try {
                        signalled = !waiters.contains(handle)
                    } finally {
                        conditionGuard.unlock()
                    }
                    if (signalled) break
                    val left = jucNanosLeft(deadline)
                    if (left <= 0L) {
                        conditionGuard.lock()
                        try {
                            waiters.remove(handle)
                        } finally {
                            conditionGuard.unlock()
                        }
                        break
                    }
                    jucPark(if (deadline < 0L) -1L else left)
                }
            } finally {
                var reacquired = 0
                while (reacquired < savedHolds) {
                    lockKernel(kernel)
                    reacquired += 1
                }
                owner = handle
                holds = savedHolds
            }
            return jucNanosLeft(deadline)
        }

        override fun signal() {
            if (!isHeldByCurrentThread) {
                throw IllegalMonitorStateException("signal by non-owner thread")
            }
            val wake: ParkingHandle?
            conditionGuard.lock()
            try {
                wake = if (waiters.isEmpty()) null else waiters.removeAt(0)
            } finally {
                conditionGuard.unlock()
            }
            if (wake != null) ParkingSupport.unpark(wake)
        }

        override fun signalAll() {
            if (!isHeldByCurrentThread) {
                throw IllegalMonitorStateException("signalAll by non-owner thread")
            }
            val wake: List<ParkingHandle>
            conditionGuard.lock()
            try {
                wake = ArrayList(waiters)
                waiters.clear()
            } finally {
                conditionGuard.unlock()
            }
            jucUnparkAll(wake)
        }
    }
}
