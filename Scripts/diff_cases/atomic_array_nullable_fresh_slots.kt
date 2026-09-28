// KUU-933: fresh AtomicArray<T?> slots must remain null across erased-T ABI calls.
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.atomicArrayOfNulls

fun main() {
    val values = atomicArrayOfNulls<Int>(2)
    println(values.loadAt(0))
    println(values.toString())
    println(values.loadAt(0) == null)
    println(values.compareAndExchangeAt(0, null, 4))
    println(values.loadAt(0))
    println(atomicArrayOfNulls<Long>(1).loadAt(0))
    println(atomicArrayOfNulls<Boolean>(1).loadAt(0))
    println(atomicArrayOfNulls<Double>(1).loadAt(0))
    println(atomicArrayOfNulls<Char>(1).loadAt(0))
    val stored = atomicArrayOfNulls<Int>(1)
    stored.storeAt(0, null)
    println(stored.loadAt(0))
}
