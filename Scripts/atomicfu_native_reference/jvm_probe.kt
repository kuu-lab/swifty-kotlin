import kotlinx.atomicfu.*
import kotlinx.atomicfu.locks.*
fun main() {
    val integer = atomic(4)
    println("scalar:${integer.compareAndSet(4, 8)}:${integer.getAndAdd(2)}:${integer.value}")
    var events = 0
    var formats = 0
    val trace = Trace(2, TraceFormat { index, event -> formats++; "$index:$event" })
    trace { events++; "event" }
    trace.append("a", "b")
    println("trace:${trace === TraceBase.None}:${trace.named("name") === TraceBase.None}:$events:$formats")
    val lock = reentrantLock()
    val result = lock.withLock { lock.withLock { 7 } }
    println("alias:$result:${lock.tryLock()}")
    lock.unlock()
    try { lock.unlock() } catch(e: Throwable) { println("unlock:${e::class.simpleName}") }
    try { AtomicIntArray(-1) } catch(e: Throwable) { println("size:${e::class.simpleName}") }
}
