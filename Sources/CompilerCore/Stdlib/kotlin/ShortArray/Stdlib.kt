package kotlin

/**
 * Kotlin stdlib `ShortArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun ShortArray(size: Int, init: (Int) -> Short): ShortArray {
    val result = ShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
