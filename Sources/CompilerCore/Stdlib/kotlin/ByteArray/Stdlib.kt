package kotlin

public inline fun ByteArray(size: Int, init: (Int) -> Byte): ByteArray {
    val result = ByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
