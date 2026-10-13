@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)
import kotlinx.atomicfu.locks.*
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.TimeSource

fun main() {
    val lock = reentrantLock()
    lock.lock()
    println(lock.tryLock())
    lock.unlock()
    lock.unlock()
    try { lock.unlock() } catch (e: IllegalArgumentException) { println("lock-owner") }
    println(lock.withLock { synchronized(lock) { 7 } })
    try { lock.withLock { throw IllegalStateException("body") } } catch (e: IllegalStateException) { println("body") }
    println(lock.tryLock())
    lock.unlock()
    val mutex = SynchronousMutex()
    mutex.lock()
    println(mutex.tryLock(Duration.ZERO))
    mutex.unlock()
    mutex.unlock()
    try { mutex.unlock() } catch (e: IllegalStateException) { println("mutex-owner") }
    println(mutex.withLock { 9 })
    val handle = ParkingSupport.currentThreadHandle()
    println(handle === ParkingSupport.currentThreadHandle())
    ParkingSupport.unpark(handle)
    ParkingSupport.unpark(handle)
    ParkingSupport.park(Duration.INFINITE)
    ParkingSupport.park(1.nanoseconds)
    ParkingSupport.unpark(handle)
    ParkingSupport.park((-1).nanoseconds)
    ParkingSupport.park(Duration.ZERO)
    ParkingSupport.parkUntil(TimeSource.Monotonic.markNow())
    println("parked")
}
