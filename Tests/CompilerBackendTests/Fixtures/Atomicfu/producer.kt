package atomicfuproducer
import kotlinx.atomicfu.*
import kotlinx.atomicfu.locks.*

private val globalCounter = atomic(1)
private val privateLock = reentrantLock()
public fun newCounter(): AtomicInt = atomic(3)
public fun nullableCounter(): AtomicRef<Int?> = atomic<Int?>(null)
public inline fun AtomicInt.bump(): Int = incrementAndGet()
public fun element(): AtomicInt {
    val array = AtomicIntArray(1)
    array[0].value = 7
    return array[0]
}
public fun nextGlobal(): Int = privateLock.withLock { globalCounter.incrementAndGet() }
