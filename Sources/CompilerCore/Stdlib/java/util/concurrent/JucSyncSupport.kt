@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlin.system.System
import kotlin.time.Duration
import kotlin.time.Duration.Companion.INFINITE
import kotlin.time.Duration.Companion.nanoseconds

// KUU-3059: shared park/unpark wait plumbing for the bundled
// java.util.concurrent blocking primitives (latch, semaphore, barrier,
// executors, locks). The atomicfu parker treats unpark-before-park as a
// coalesced permit, so a registered handle can be unparked at any point
// without a missed wakeup. A negative timeout means "wait forever".

internal fun jucNanosToDuration(nanos: Long): Duration = when {
    nanos < 0L -> INFINITE
    else -> nanos.nanoseconds
}

/** Parks the current thread for up to [nanos]; a negative value waits forever. */
internal fun jucPark(nanos: Long): Unit = ParkingSupport.park(jucNanosToDuration(nanos))

internal fun jucUnparkAll(handles: List<ParkingHandle>) {
    for (handle in handles) {
        ParkingSupport.unpark(handle)
    }
}

/** Absolute [System.nanoTime] deadline for a relative [nanos] wait; -1 stays -1. */
internal fun jucDeadlineNanos(nanos: Long): Long =
    if (nanos < 0L) -1L else System.nanoTime() + nanos

/**
 * Nanos remaining until [deadlineNanos]; negative when expired.
 * A negative deadline reports [Long.MAX_VALUE] (no expiry).
 */
internal fun jucNanosLeft(deadlineNanos: Long): Long =
    if (deadlineNanos < 0L) Long.MAX_VALUE else deadlineNanos - System.nanoTime()
