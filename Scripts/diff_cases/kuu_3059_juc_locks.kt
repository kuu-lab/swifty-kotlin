import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import java.util.concurrent.locks.ReentrantReadWriteLock

// KUU-3059: java.util.concurrent.locks surface. All single-threaded —
// conditions can only be queried, not awaited, without a second thread.
fun main() {
    val lock = ReentrantLock()
    println(lock.isLocked)                  // false
    lock.lock()
    println(lock.isLocked)                  // true
    println(lock.isHeldByCurrentThread)     // true
    println(lock.tryLock())                   // true (reentrant)
    println(lock.holdCount)                   // 2
    lock.unlock()
    lock.unlock()
    println(lock.isLocked)                  // false
    println(lock.tryLock(1, TimeUnit.SECONDS)) // true
    lock.unlock()

    val rw = ReentrantReadWriteLock()
    val read = rw.readLock()
    val write = rw.writeLock()
    read.lock()
    read.lock()
    println(rw.readHoldCount)            // 2
    println(rw.readLockCount)            // 2
    println(write.tryLock())                  // false (readers hold)
    read.unlock()
    read.unlock()
    println(write.tryLock())                  // true
    println(rw.isWriteLocked)                 // true
    println(rw.isWriteLockedByCurrentThread)  // true
    println(read.tryLock())                   // true (reader under writer)
    read.unlock()
    write.unlock()
    println(rw.isWriteLocked)                 // false

    val notHeld = ReentrantLock()
    try {
        notHeld.unlock()
        println("unreachable")
    } catch (e: IllegalMonitorStateException) {
        println("illegal-monitor")            // illegal-monitor
    }
}
