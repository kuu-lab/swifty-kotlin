package kotlin

// KSP-783: Keep the primitive LongArray factory source-backed. The vararg
// parameter is represented as a LongArray, so copy its elements into the
// result allocated by the primitive-array constructor.
public inline fun longArrayOf(vararg elements: Long): LongArray {
    val result = LongArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index += 1
    }
    return result
}
