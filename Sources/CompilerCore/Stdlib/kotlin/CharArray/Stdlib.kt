package kotlin

public inline fun CharArray(size: Int, init: (Int) -> Char): CharArray {
    val result = CharArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
