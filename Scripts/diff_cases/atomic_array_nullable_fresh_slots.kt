// KUU-933: fresh AtomicArray<T?> slots must remain null across erased-T ABI calls.
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicArray
import kotlin.concurrent.atomics.atomicArrayOfNulls

fun main() {
    val values = AtomicArray<Int?>(2)
    println(values.loadAt(0))
    println(values.toString())
    println(values.loadAt(0) == null)
    println(values.compareAndExchangeAt(0, null, 4))
    println(values.loadAt(0))
    println(atomicArrayOfNulls<Int>(1).loadAt(0))
    println(AtomicArray<Long?>(1).loadAt(0))
    println(AtomicArray<Boolean?>(1).loadAt(0))
    println(AtomicArray<Double?>(1).loadAt(0))
    println(AtomicArray<Char?>(1).loadAt(0))
    val stored = AtomicArray<Int?>(1)
    stored.storeAt(0, null)
    println(stored.loadAt(0))
}
