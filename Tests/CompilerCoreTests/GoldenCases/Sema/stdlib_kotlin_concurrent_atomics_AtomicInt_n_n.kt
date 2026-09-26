@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicInt

fun atomicIntConstructorSemantics(): Int {
    val zeroValue = AtomicInt(0)
    val intValue = AtomicInt(42)
    return zeroValue.load() + intValue.load()
}
