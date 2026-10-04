package kotlin

import kotlin.internal.KsSymbolName

// Kotlin's UShortArray storage constructor is @PublishedApi internal. The
// primitive-array representation cannot declare a Kotlin class constructor, so
// keep the same internal source-backed overload as a runtime view bridge.
@KsSymbolName("__kk_shortArray_asUShortArray")
@PublishedApi
internal external fun UShortArray(storage: ShortArray): UShortArray

public inline fun UShortArray(size: Int, init: (Int) -> UShort): UShortArray {
    val result = UShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
