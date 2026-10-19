@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.internal.KsSymbolName

/**
 * Creates an atomic integer array of the requested size, initialized to zero.
 *
 * The allocation remains in the runtime box.
 */
@SinceKotlin("1.9")
@ExperimentalStdlibApi
@KsSymbolName("kk_atomic_int_array_create")
public external fun AtomicIntArray(size: Int): AtomicIntArray

/**
 * This overload is an internal stdlib implementation entry point in Kotlin's
 * Native source and is kept out of consumer metadata.
 */
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
