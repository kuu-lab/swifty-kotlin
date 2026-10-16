// Minimal API fixture based on Ktor 3.6.0 ktor-io/common Synchronized.kt.
package io.ktor.utils.io.locks

public expect open class SynchronizedObject()

public expect class ReentrantLock {
    public fun lock()
    public fun tryLock(): Boolean
    public fun unlock()
}

public expect fun reentrantLock(): ReentrantLock

public expect inline fun <T> ReentrantLock.withLock(block: () -> T): T

public expect inline fun <T> synchronized(lock: SynchronizedObject, block: () -> T): T
