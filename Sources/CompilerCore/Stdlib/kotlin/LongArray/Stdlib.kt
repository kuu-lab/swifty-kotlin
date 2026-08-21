package kotlin

// KSP-861: Keep the initializer overload source-backed while the size-only
// primitive-array constructor remains a compiler-provided allocation primitive.
public inline fun LongArray(size: Int, init: (Int) -> Long): LongArray {
    val result = LongArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index += 1
    }
    return result
}
