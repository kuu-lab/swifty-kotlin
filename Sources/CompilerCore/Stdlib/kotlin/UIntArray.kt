package kotlin

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

@ExperimentalUnsignedTypes
@PublishedApi
internal fun UIntArray(storage: IntArray): UIntArray = storage.asUIntArray()
