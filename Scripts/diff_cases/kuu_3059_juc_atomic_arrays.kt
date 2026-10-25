import java.util.concurrent.atomic.AtomicIntegerArray
import java.util.concurrent.atomic.AtomicLongArray
import java.util.concurrent.atomic.AtomicReferenceArray

// KUU-3059: java.util.concurrent.atomic array classes over the shared
// runtime array boxes. Deterministic single-thread output for the diff gate.
fun main() {
    val ints = AtomicIntegerArray(3)
    ints.set(0, 7)
    println(ints.get(0))                        // 7
    println(ints.incrementAndGet(1))            // 1
    println(ints.getAndAdd(2, 40))              // 0
    println(ints.get(2))                        // 40
    println(ints.compareAndSet(0, 7, 9))        // true
    println(ints.getAndSet(0, 3))               // 9
    println(ints.length())                      // 3
    ints.lazySet(1, 5)
    println(ints[1])                            // 5
    println(ints.getAndUpdate(1) { it * 10 })   // 5
    println(ints.updateAndGet(1) { it + 1 })    // 51
    println(ints)                               // [3, 51, 40]

    val longs = AtomicLongArray(2)
    longs.set(0, 1_000_000_000_000L)
    println(longs.get(0))                       // 1000000000000
    println(longs.addAndGet(1, 5L))             // 5
    println(longs.compareAndSet(1, 5L, 8L))     // true
    println(longs.length())                     // 2
    println(longs.getAndAccumulate(0, 3L) { a, b -> a + b }) // 1000000000000
    println(longs.get(0))                       // 1000000000003

    val a = "a"
    val refs = AtomicReferenceArray<String>(2)
    refs.set(0, a)
    println(refs.get(0))                        // a
    println(refs.compareAndSet(0, a, "b"))      // true (identity)
    println(refs.get(0))                        // b
    println(refs.getAndSet(1, "c"))             // null
    println(refs.get(1))                        // c
    println(refs.length())                      // 2
    println(refs.getAndUpdate(1) { it + "!" })  // c
    println(refs.get(1))                        // c!
}
