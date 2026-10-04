package kotlin

// The stdlib keeps the ByteArray-backed constructor internal and published for
// inline implementations. Reuse the existing view bridge so the constructor
// preserves the underlying storage rather than copying it.
@PublishedApi
internal fun UByteArray(storage: ByteArray): UByteArray = storage.asUByteArray()

public inline fun UByteArray(size: Int, init: (Int) -> UByte): UByteArray {
    val result = UByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
