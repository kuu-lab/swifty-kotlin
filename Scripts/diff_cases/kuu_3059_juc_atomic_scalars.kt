import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

// KUU-3059: java.util.concurrent.atomic scalar surface beyond AtomicInteger.
// Every line must print identically under kswiftc and reference kotlinc.
fun main() {
    val ai = AtomicInteger(1)
    println(ai.incrementAndGet())          // 2
    println(ai.getAndAdd(10))              // 2
    println(ai.get())                      // 12
    println(ai.compareAndSet(12, 20))      // true
    println(ai.getAndSet(5))               // 20
    ai.lazySet(7)
    println(ai.get())                      // 7
    println(ai.getAndUpdate { it * 2 })    // 7
    println(ai.updateAndGet { it + 1 })    // 15
    println(ai.accumulateAndGet(5) { a, b -> a + b }) // 20

    val al = AtomicLong(5L)
    println(al.get())                      // 5
    println(al.addAndGet(3L))              // 8
    println(al.compareAndSet(8L, 1L))      // true
    println(al.decrementAndGet())          // 0
    println(al.getAndUpdate { it + 100L }) // 0
    println(al.get())                      // 100

    val ab = AtomicBoolean(false)
    println(ab.get())                      // false
    println(ab.compareAndSet(false, true)) // true
    println(ab.getAndSet(false))           // true
    ab.lazySet(true)
    println(ab.get())                      // true
    println(ab.compareAndExchange(true, false)) // true

    val x = "x"
    val ar = AtomicReference(x)
    println(ar.get())                      // x
    println(ar.compareAndSet(x, "y"))      // true (identity on the same object)
    println(ar.get())                      // y
    println(ar.getAndSet("z"))             // y
    println(ar.getAndUpdate { it + "!" })  // z
    println(ar.get())                      // z!
    println(ar.updateAndGet { it + "?" })  // z!?
}
