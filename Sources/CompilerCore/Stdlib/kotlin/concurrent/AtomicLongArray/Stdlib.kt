@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.internal.KsSymbolName

@SinceKotlin("1.9")
@ExperimentalStdlibApi
@KsSymbolName("kk_atomic_long_array_create")
public external fun AtomicLongArray(size: Int): AtomicLongArray

@SinceKotlin("1.9")
@ExperimentalStdlibApi
@PublishedApi
internal fun AtomicLongArray(array: LongArray): AtomicLongArray {
    val result = AtomicLongArray(array.size)
    var index = 0
    while (index < array.size) {
        result[index] = array[index]
        index++
    }
    return result
}
