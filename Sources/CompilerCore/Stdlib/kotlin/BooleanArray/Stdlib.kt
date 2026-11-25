package kotlin

public inline fun BooleanArray(size: Int, init: (Int) -> Boolean): BooleanArray {
    val result = BooleanArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
