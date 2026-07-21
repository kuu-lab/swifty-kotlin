@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicReference

fun main() {
    // AtomicReference basics
    val ar = AtomicReference("hello")
    println(ar.load())              // hello
    ar.store("world")
    println(ar.load())              // world
    println(ar.exchange("foo"))     // world
    println(ar.load())              // foo
    println(ar.compareAndSet("missing", "ignored")) // false
    println(ar.compareAndSet("foo", "bar"))   // true
    println(ar.compareAndExchange("bar", "baz")) // bar
    // JVM kotlinc 2.3.10 does not resolve AtomicReference.getAndUpdate / updateAndGet;
    // keep behaviour identical via CAS loops so kswiftc vs kotlinc diff stays aligned.
    run {
        while (true) {
            val cur = ar.load()
            val next = cur + "!"
            if (ar.compareAndSet(cur, next)) {
                println(cur)
                break
            }
        }
    }
    run {
        while (true) {
            val cur = ar.load()
            val next = cur + "?"
            if (ar.compareAndSet(cur, next)) {
                println(next)
                break
            }
        }
    }
    println(ar.load())                          // baz!?

    val count = AtomicInt(1)
    println(count.load())
    println(count.addAndFetch(4))
    println(count.fetchAndAdd(3))
    println(count.compareAndExchange(8, 10))
    println(count.compareAndExchange(9, 10))
    println(count.load())
}
