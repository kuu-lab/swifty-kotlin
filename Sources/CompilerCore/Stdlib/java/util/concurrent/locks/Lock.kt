package java.util.concurrent.locks

import java.util.concurrent.TimeUnit

// KUU-3059: java.util.concurrent.locks.Lock / Condition — the explicit
// lock contract implemented by ReentrantLock and ReentrantReadWriteLock.
public interface Lock {
    public fun lock()

    public fun lockInterruptibly()

    public fun tryLock(): Boolean

    public fun tryLock(time: Long, unit: TimeUnit): Boolean

    public fun unlock()

    public fun newCondition(): Condition
}
