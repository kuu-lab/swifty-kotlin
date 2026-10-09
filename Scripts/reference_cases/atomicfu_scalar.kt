// JVM reference only: atomicfu-jvm 0.33.0, Kotlin 2.3.10.
// Source baseline: Kotlin/kotlinx-atomicfu fc175fc575419ca9eae0d3c14cefe9c5cd7ca351.
// This uses the real library without the atomicfu compiler plugin.
import kotlinx.atomicfu.atomic

fun main() {
    val intValue = atomic(1)
    println(intValue.compareAndSet(1, 2))
    println(intValue.compareAndSet(1, 3))
    println(intValue.incrementAndGet())
    val longValue = atomic(7L)
    println(longValue.getAndAdd(2L))
    println(longValue.value)
    val booleanValue = atomic(false)
    println(booleanValue.compareAndSet(false, true))
    println(booleanValue.value)
    val first = Any()
    val reference = atomic(first)
    println(reference.compareAndSet(Any(), Any()))
    val second = Any()
    println(reference.compareAndSet(first, second))
    println(reference.value === second)
}
