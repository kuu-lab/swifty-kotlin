package java.util.concurrent.locks

import java.util.concurrent.TimeUnit

public interface Lock {
    public fun lock()

    public fun lockInterruptibly()

    public fun tryLock(): Boolean

    public fun tryLock(time: Long, unit: TimeUnit): Boolean

    public fun unlock()

    public fun newCondition(): Condition
}
