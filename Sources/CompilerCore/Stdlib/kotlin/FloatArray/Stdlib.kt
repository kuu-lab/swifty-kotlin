package kotlin

public inline fun FloatArray(size: Int, init: (Int) -> Float): FloatArray {
    val result = FloatArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
