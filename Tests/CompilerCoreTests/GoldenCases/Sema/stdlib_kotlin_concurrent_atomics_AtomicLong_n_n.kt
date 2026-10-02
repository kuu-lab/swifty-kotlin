@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicLong

fun atomicLongConstructorSemantics(): Long {
    val zeroValue = AtomicLong(0L)
    val longValue = AtomicLong(42L)
    return zeroValue.load() + longValue.load()
}
