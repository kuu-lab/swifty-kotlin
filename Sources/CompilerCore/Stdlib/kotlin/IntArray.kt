package kotlin

/**
 * Kotlin stdlib `IntArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
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
