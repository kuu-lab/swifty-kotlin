package kotlin

public inline fun ShortArray(size: Int, init: (Int) -> Short): ShortArray {
    val result = ShortArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
