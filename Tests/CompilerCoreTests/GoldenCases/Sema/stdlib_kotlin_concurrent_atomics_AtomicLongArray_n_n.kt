@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicLongArray

fun atomicLongArrayConstructors(values: LongArray): Long {
    val fromSize = AtomicLongArray(3)
    val fromArray = AtomicLongArray(values)
    return fromSize.loadAt(0) + fromArray.loadAt(1)
}
