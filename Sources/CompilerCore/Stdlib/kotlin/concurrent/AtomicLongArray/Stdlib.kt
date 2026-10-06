@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.internal.KsSymbolName

/**
 * Creates an atomic long array of the requested size, initialized to zero.
 *
 * The allocation remains in the runtime box; this declaration provides the
 * source-backed stdlib entry point for the existing runtime ABI.
 */
@SinceKotlin("1.9")
@ExperimentalStdlibApi
@KsSymbolName("kk_atomic_long_array_create")
public external fun AtomicLongArray(size: Int): AtomicLongArray

/**
 * Creates an atomic long array from a copy of the supplied array.
 *
 * This overload is an internal stdlib implementation entry point in Kotlin's
 * Native source and is kept out of consumer metadata.
 */
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
