package kotlin

public inline fun UByteArray(size: Int, init: (Int) -> UByte): UByteArray {
    val result = UByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
