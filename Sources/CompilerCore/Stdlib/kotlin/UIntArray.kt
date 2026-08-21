package kotlin

/**
 * Kotlin stdlib `UIntArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun UIntArray(size: Int, init: (Int) -> UInt): UIntArray {
    val result = UIntArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
