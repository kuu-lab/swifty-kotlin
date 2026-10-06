@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicArray
import kotlin.concurrent.atomics.AtomicBoolean
import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicIntArray
import kotlin.concurrent.atomics.AtomicLong
import kotlin.concurrent.atomics.AtomicLongArray
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.atomicArrayOfNulls

fun atomicIntType(): AtomicInt? = null
fun atomicLongType(): AtomicLong? = null
fun atomicBooleanType(): AtomicBoolean? = null
fun atomicReferenceType(value: AtomicReference<String>): AtomicReference<String> = value
fun atomicArrayType(value: AtomicArray<String?>): AtomicArray<String?> = value

fun main() {
    val flag = AtomicBoolean(true)
    println(flag.compareAndSet(true, false))
    println(flag.load())

    val count = AtomicInt(1)
    println(count.addAndFetch(4))
    println(count.fetchAndAdd(3))
    println(count.compareAndSet(8, 10))
    println(count.load())

    val longCount = AtomicLong(7L)
    println(longCount.load())

    val ref = AtomicReference("initial")
    ref.store("stored")
    println(ref.load())
    println(ref.compareAndExchange("stored", "done"))

    val nulls = atomicArrayOfNulls<String>(2)
    println(nulls.loadAt(0))
    nulls.storeAt(0, "x")
    println(nulls.loadAt(0))

    val arr = AtomicArray(2) { "item$it" }
    println(arr.loadAt(1))

    val ints = AtomicIntArray(2) { it }
    println(ints.loadAt(1))
    val longs = AtomicLongArray(2) { it.toLong() }
    println(longs.loadAt(0))
}
