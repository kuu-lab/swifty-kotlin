package kotlinx.atomicfu.locks
public class AppleTestReentrantLock {
    private val lock = platform.Foundation.NSRecursiveLock()
    public fun lock() { lock.lock() }
    public fun unlock() { lock.unlock() }
}
public fun reentrantLock(): AppleTestReentrantLock = AppleTestReentrantLock()
public inline fun <R> AppleTestReentrantLock.withLock(block: () -> R): R {
    lock()
    try { return block() } finally { unlock() }
}
