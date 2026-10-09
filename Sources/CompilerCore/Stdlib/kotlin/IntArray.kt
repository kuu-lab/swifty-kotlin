package kotlin

import kotlin.internal.KsSymbolName

// Expose the size-only intrinsic as a declaration so callable references
// can select it through ordinary overload resolution (KUU-1276).
@KsSymbolName("kk_array_new_checked")
public external fun IntArray(size: Int): IntArray

/**
 * Kotlin stdlib `IntArray(size) { init }` constructor.
 *
 * This overload is implemented as ordinary bundled Kotlin source.
 */
public inline fun IntArray(size: Int, init: (Int) -> Int): IntArray {
    val result = IntArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
