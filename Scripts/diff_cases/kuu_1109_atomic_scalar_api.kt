@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*
import java.util.concurrent.atomic.AtomicInteger

fun main() {
    val ai = AtomicInt(0)
    println(ai.fetchAndAdd(3))
    println(ai.addAndFetch(2))
    println(ai.fetchAndIncrement())
    println(ai.incrementAndFetch())
    println(ai.fetchAndDecrement())
    println(ai.decrementAndFetch())
    println(ai.exchange(10))
    println(ai.compareAndExchange(10, 20))
    println(ai.compareAndExchange(10, 30))
    println(ai.fetchAndUpdate { it + 1 })
    println(ai.updateAndFetch { it + 1 })
    ai.update { it * 2 }
    println(ai.load())

    val al = AtomicLong(0L)
    println(al.fetchAndAdd(3L))
    println(al.addAndFetch(2L))
    println(al.fetchAndIncrement())
    println(al.incrementAndFetch())
    println(al.fetchAndDecrement())
    println(al.decrementAndFetch())
    println(al.exchange(10L))
    println(al.compareAndExchange(10L, 20L))
    println(al.fetchAndUpdate { it + 1L })
    println(al.updateAndFetch { it + 1L })
    al.update { it * 2L }
    println(al.load())

    val ar = AtomicReference<String?>("x")
    println(ar.exchange(null))
    println(ar.load())
    println(ar.fetchAndUpdate { "z" })
    println(ar.updateAndFetch { "a" })
    ar.update { "b" }
    println(ar.load())
    println(ar.compareAndExchange(ar.load(), "c"))
    println(ar.load())

    val ab = AtomicBoolean(true)
    println(ab.exchange(false))
    println(ab.compareAndSet(false, true))
    println(ab.load())

    val java = AtomicInteger(0)
    println(java.getAndAdd(3))
    println(java.addAndGet(2))
    println(java.getAndIncrement())
    println(java.incrementAndGet())
    println(java.getAndDecrement())
    println(java.decrementAndGet())
    println(java.getAndSet(10))
    java.set(20)
    println(java.get())
}
