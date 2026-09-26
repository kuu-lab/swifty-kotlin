@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicArray

fun atomicArrayConstructors(values: Array<String>): Int {
    val fromSize = AtomicArray<String>(3)
    val fromArray = AtomicArray(values)
    val first: String? = fromArray.loadAt(0)
    return fromSize.size + fromArray.size
}
