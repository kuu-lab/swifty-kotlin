@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.internal.KsSymbolName

@SinceKotlin("1.9")
@ExperimentalStdlibApi
@KsSymbolName("kk_atomic_int_array_create")
public external fun AtomicIntArray(size: Int): AtomicIntArray

@SinceKotlin("1.9")
@ExperimentalStdlibApi
@PublishedApi
internal fun AtomicIntArray(array: IntArray): AtomicIntArray {
    val result = AtomicIntArray(array.size)
    var index = 0
    while (index < array.size) {
        result[index] = array[index]
        index++
    }
    return result
}
