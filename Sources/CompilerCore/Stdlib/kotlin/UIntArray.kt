package kotlin

/**
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
@ExperimentalUnsignedTypes
public inline fun UIntArray(size: Int, init: (Int) -> UInt): UIntArray {
    val result = UIntArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}

/**
 * Kotlin exposes this constructor only to the stdlib implementation. The
 * signed and unsigned arrays intentionally share the same backing storage.
 */
@ExperimentalUnsignedTypes
@PublishedApi
internal fun UIntArray(storage: IntArray): UIntArray = storage.asUIntArray()
