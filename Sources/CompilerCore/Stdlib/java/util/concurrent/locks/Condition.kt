package java.util.concurrent.locks

import java.util.concurrent.TimeUnit

public interface Condition {
    public fun await()

    public fun await(time: Long, unit: TimeUnit): Boolean

    public fun awaitNanos(nanosTimeout: Long): Long

    public fun signal()

    public fun signalAll()
}
