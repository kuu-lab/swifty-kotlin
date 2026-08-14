@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicReference

data class Token(val value: String)

fun main() {
    // AtomicReference basics
    val hello = Token("hello")
    val world = Token("world")
    val foo = Token("foo")
    val bar = Token("bar")
    val baz = Token("baz")
    val ar = AtomicReference(hello)
    println(ar.load().value)              // hello
    ar.store(world)
    println(ar.load().value)              // world
    println(ar.exchange(foo).value)       // world
    println(ar.load().value)              // foo
    println(ar.compareAndSet(Token("missing"), Token("ignored"))) // false
    println(ar.compareAndSet(foo, bar))   // true
    println(ar.compareAndExchange(bar, baz).value) // bar
    // JVM kotlinc 2.3.10 does not resolve AtomicReference.getAndUpdate / updateAndGet;
    // keep behaviour identical via CAS loops so kswiftc vs kotlinc diff stays aligned.
    run {
        while (true) {
            val cur = ar.load()
            val next = Token(cur.value + "!")
            if (ar.compareAndSet(cur, next)) {
                println(cur.value)
                break
            }
        }
    }
    run {
        while (true) {
            val cur = ar.load()
            val next = Token(cur.value + "?")
            if (ar.compareAndSet(cur, next)) {
                println(next.value)
                break
            }
        }
    }
    println(ar.load().value)                    // baz!?

    val count = AtomicInt(1)
    println(count.load())
    println(count.addAndFetch(4))
    println(count.fetchAndAdd(3))
    println(count.compareAndExchange(8, 10))
    println(count.compareAndExchange(9, 10))
    println(count.load())
}
