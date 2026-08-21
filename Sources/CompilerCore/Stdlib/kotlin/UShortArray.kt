package kotlin

public inline fun UShortArray(size: Int, init: (Int) -> UShort): UShortArray {
    val result = UShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
