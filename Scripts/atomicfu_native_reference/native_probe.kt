@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)
import kotlinx.atomicfu.*
import kotlinx.atomicfu.locks.*
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
fun main() {
    val integer = atomic(4)
    println("scalar:${integer.compareAndSet(4, 8)}:${integer.getAndAdd(2)}:${integer.value}")
    var events = 0
    var formats = 0
    val trace = Trace(2, TraceFormat { index, event -> formats++; "$index:$event" })
    trace { events++; "event" }
    trace.append("a", "b")
    println("trace:${trace === TraceBase.None}:${trace.named("name") === TraceBase.None}:$events:$formats")
    val lock: ReentrantLock = SynchronizedObject()
    val result = lock.withLock { lock.withLock { 7 } }
    println("alias:$result:${lock.tryLock()}")
    lock.unlock()
    try { lock.unlock() } catch(e: Throwable) { println("unlock:${e::class.simpleName}") }
    val handle = ParkingSupport.currentThreadHandle()
    check(handle === ParkingSupport.currentThreadHandle())
    ParkingSupport.unpark(handle)
    ParkingSupport.park(Duration.INFINITE)
    ParkingSupport.park(1.milliseconds)
    println("parking:returned")
    try { AtomicIntArray(-1) } catch(e: Throwable) { println("size:${e::class.simpleName}") }
}
