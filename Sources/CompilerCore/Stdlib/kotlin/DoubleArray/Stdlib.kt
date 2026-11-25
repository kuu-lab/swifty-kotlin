package kotlin

public inline fun DoubleArray(size: Int, init: (Int) -> Double): DoubleArray {
    val result = DoubleArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
