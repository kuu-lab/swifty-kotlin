// Minimal API fixture based on Ktor 3.6.0 ktor-io/posix Synchronized.kt.
package io.ktor.utils.io.locks

public actual open class SynchronizedObject {
    public fun lock() {}
    public fun tryLock(): Boolean = true
    public fun unlock() {}
}

public actual typealias ReentrantLock = SynchronizedObject

public actual fun reentrantLock(): ReentrantLock = ReentrantLock()

public actual inline fun <T> ReentrantLock.withLock(block: () -> T): T {
    lock()
    try {
        return block()
    } finally {
        unlock()
    }
}

public actual inline fun <T> synchronized(lock: SynchronizedObject, block: () -> T): T {
    lock.lock()
    try {
        return block()
    } finally {
        lock.unlock()
    }
}
