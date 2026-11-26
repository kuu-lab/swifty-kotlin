package kotlin

@ExperimentalUnsignedTypes
public inline fun ULongArray(size: Int, init: (Int) -> ULong): ULongArray {
    val result = ULongArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index += 1
    }
    return result
}

@ExperimentalUnsignedTypes
@PublishedApi
internal fun ULongArray(storage: LongArray): ULongArray = storage.asULongArray()
