@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicIntArray

fun atomicIntArrayConstructors(values: IntArray): Int {
    val fromSize = AtomicIntArray(3)
    val fromArray = AtomicIntArray(values)
    return fromSize.loadAt(0) + fromArray.loadAt(1)
}
