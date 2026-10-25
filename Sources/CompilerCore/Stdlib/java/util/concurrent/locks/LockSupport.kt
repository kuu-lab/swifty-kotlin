@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent.locks

import kotlinx.atomicfu.locks.ParkingSupport
import kotlin.system.System
import kotlin.time.Duration.Companion.INFINITE
import kotlin.time.Duration.Companion.nanoseconds

// KUU-3059: java.util.concurrent.locks.LockSupport — thread-park facade over
// the atomicfu parker. unpark requires a Thread handle that does not exist
// in this runtime yet, so only the park family is surfaced.

public object LockSupport {
    public fun park() {
        ParkingSupport.park(INFINITE)
    }

    public fun parkNanos(nanos: Long) {
        if (nanos > 0L) ParkingSupport.park(nanos.nanoseconds)
    }

    public fun parkUntil(deadlineMillis: Long) {
        val now = System.currentTimeMillis()
        val left = deadlineMillis - now
        if (left > 0L) parkNanos(left * 1_000_000L)
    }
}
